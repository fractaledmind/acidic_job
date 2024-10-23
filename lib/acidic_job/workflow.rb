# frozen_string_literal: true

require "active_job"

module AcidicJob
  class Workflow < ActiveJob::Base
    module ClassMethods
      attr_reader :unique_by, :steps

      # provide a default mechanism for identifying unique job runs
      # typical: [self.class.name, self.arguments]
      def unique_by(proc = nil, &block)
        @unique_by = proc || block
      end

      def execute(method_name, if: nil, unless: nil, transactional: nil, idempotency_check: nil, compensate_with: nil, rollback_on: nil)
        @steps ||= []
        definition = { "does" => method_name.to_s }

        define_if!(definition, binding.local_variable_get(:if))
        define_unless!(definition, binding.local_variable_get(:unless))
        define_transactional!(definition, transactional)
        define_idempotency_check!(definition, idempotency_check)
        define_compensate_with!(definition, compensate_with)
        define_rollback_on!(definition, rollback_on)

        @steps << definition
        @steps
      end

      def await(jobs_batch, if: nil, unless: nil, transactional: nil, idempotency_check: nil, compensate_with: nil, rollback_on: nil)
        @steps ||= []
        definition = { "does" => "step_#{@steps.size + 1}" }

        define_awaits!(definition, jobs_batch)

        define_if!(definition, binding.local_variable_get(:if))
        define_unless!(definition, binding.local_variable_get(:unless))
        define_transactional!(definition, transactional)
        define_idempotency_check!(definition, idempotency_check)
        define_compensate_with!(definition, compensate_with)
        define_rollback_on!(definition, rollback_on)

        @steps << definition
        @steps
      end

      def traverse(collection, using:, if: nil, unless: nil, transactional: nil, idempotency_check: nil, compensate_with: nil, rollback_on: nil)
        @steps ||= []
        definition = { "does" => using.to_s }

        define_for_each!(definition, collection)

        define_if!(definition, binding.local_variable_get(:if))
        define_unless!(definition, binding.local_variable_get(:unless))
        define_transactional!(definition, transactional)
        define_idempotency_check!(definition, idempotency_check)
        define_compensate_with!(definition, compensate_with)
        define_rollback_on!(definition, rollback_on)

        @steps << definition
        @steps
      end

      def delay(instruction, if: nil, unless: nil)
        @steps ||= []
        definition = { "does" => "step_#{@steps.size + 1}" }

        define_delay!(definition, instruction)

        define_if!(definition, binding.local_variable_get(:if))
        define_unless!(definition, binding.local_variable_get(:unless))

        @steps << definition
        @steps
      end

      private

        def define_if!(definition, arg)
          return definition unless arg
          raise ArgumentError, "The `if` argument must be a method name" unless arg in Symbol | String

          definition.merge!("if" => arg.to_s)
        end

        def define_unless!(definition, arg)
          return definition unless arg
          raise ArgumentError, "The `unless` argument must be a method name" unless arg in Symbol | String

          definition.merge!("unless" => arg.to_s)
        end

        def define_transactional!(definition, arg)
          return unless arg
          raise ArgumentError, "The `transactional` argument must be boolean" unless arg in true | false

          definition.merge!("transactional" => arg)
        end

        def define_awaits!(definition, arg)
          return definition unless arg
          raise ArgumentError, "" unless arg in Array | Symbol | String

          definition.merge!("awaits" => arg)
        end

        def define_for_each!(definition, arg)
          return definition unless arg
          raise ArgumentError, "" unless arg in Enumerable | Symbol | String

          definition.merge!("for_each" => arg)
        end

        def define_delay!(definition, arg)
          return definition unless arg
          raise ArgumentError, "" unless arg in Numeric | ActiveSupport::Duration |
                                                Hash[for: Numeric | ActiveSupport::Duration, until: Symbol | String]

          definition.merge!("delay" => arg)
        end

        def define_idempotency_check!(definition, arg)
          return unless arg
          raise ArgumentError, "The `idempotency_check` argument must be a method name" unless arg in Symbol | String

          definition.merge!("idempotency_check" => idempotency_check)
        end

        def define_compensate_with!(definition, arg)
          return unless arg
          raise ArgumentError, "The `compensate_with` argument must be a method name" unless arg in Symbol | String

          definition.merge!("compensate_with" => arg)
        end

        def define_rollback_on!(definition, arg)
          return unless arg
          raise ArgumentError, "The `rollback_on` argument must be some error(s)" unless arg in Module | Array[Module]

          definition.merge!("rollback_on" => Array(arg))
        end
    end

    extend ClassMethods

    def perform(*args)
      AcidicJob.instrument(:initialize_execution, job: self) do
        @execution = initialize_execution
      end
      @ctx ||= Context.new(@execution)

      # if the workflow record is already marked as finished, immediately return its result
      return true if @execution.finished?

      loop do
        break if @execution.finished?

        raise UndefinedStepError, @execution.recover_to_step if not @execution.definition.key?(@execution.recover_to_step)

        step_definition = @execution.definition[@execution.recover_to_step]
        awaited_jobs = awaited_jobs_for(step_definition)

        if awaited_jobs.any?
          # We only execute the current step, without progressing to the next step.
          # This ensures that any failures in parallel jobs will have this step retried in the main workflow
          next_step = take_step(step_definition)
          # We allow the `#step_done` method to manage progressing the recovery_point to the next step,
          # and then calling `process_run` to restart the main workflow on the next step.

          AcidicJob::BatchedJob.insert_all(
            awaited_jobs.map do |awaited_job|
              { execution_id: @execution.id,
                job_id: awaited_job.job_id,
                serialized_job: awaited_job.serialize,
                progress_to: next_step }
            end
          )

          awaited_jobs.each do |awaited_job|
            awaited_job.enqueue
          end

          # after processing the current step, break the processing loop
          # and halt the active job, allowing this worker to be reused
          # this MUST be `return` to exit the parent job
          return true
        elsif step_definition["delay"]
          delay = nil
          if Hash === step_definition["delay"]
            if (delay_check = step_definition.dig("delay", "until"))
              if resolve_method(delay_check).call
                @execution.update!(recover_to: step_definition.fetch("then"))

                # the until method return truthy, so we can progress to the next step
                next
              end
            end

            delay = step_definition.dig("delay", "for")
          else
            delay = step_definition["delay"]
          end

          self.class.set(wait: delay).perform_later(*args)

          return true
        else
          next_step = take_step(step_definition)
          @execution.update!(recover_to: next_step)
        end
      end

      true
    end

    private

      def definition
        return @definition if defined? @definition

        # Don't mutate the original steps array, since it is an instance variable on the class.
        steps = self.class.steps.dup
        # [ { does: "step 1", awaits: [] }, { does: "step 2", awaits: [] }, ... ]

        raise MissingStepsError if steps.empty?

        steps << { "does" => FINISHED_RECOVERY_POINT } unless steps.last["does"] == FINISHED_RECOVERY_POINT
        @definition = {}.tap do |workflow|
          steps.each_cons(2).map do |enter_step, exit_step|
            enter_name = enter_step["does"]
            raise DuplicateStepError, enter_name if workflow.key?(enter_name)

            workflow[enter_name] = enter_step.merge("then" => exit_step["does"])
          end
        end
        # { "step 1": { does: "step 1", awaits: [], then: "step 2" }, ...  }
      end

      # encode the job run identifier as a hex string
      def idempotency_key
        return job_id unless self.class.unique_by
        return @idempotency_key if defined? @idempotency_key

        unique_by = instance_exec(&self.class.unique_by)
        @idempotency_key = Digest::SHA1.hexdigest([self.class.name, proc_result].flatten.join)
      end

      def initialize_execution
        transaction_args = case ::ActiveRecord::Base.connection.adapter_name.downcase.to_sym
                          # SQLite only really runs `serializable` transactions
                          when :sqlite
                            {}
                          else
                            { isolation: :serializable }
                          end

        ::ActiveRecord::Base.transaction(**transaction_args) do
          record = Execution.find_by(idempotency_key: idempotency_key)
          serialized_job = serialize

          if record.present?
            # The recorded workflow arguments must match the current ones for the job.
            if record.serialized_job["arguments"] != serialized_job["arguments"]
              # TODO: add a way to compare arguments
              raise ArgumentMismatchError
            end

            # The recorded workflow definition must match the current one for the job.
            if record.definition != definition
              # TODO: add a way to compare definitions
              raise DefinitionMismatchError
            end

            # Only acquire a lock if the key is unlocked or its lock has expired
            # because the original job was long enough ago.
            # raise "LockedIdempotencyKey" if record.locked_at > Time.current - 2.seconds

            record.update!(
              last_run_at: Time.current
            )
          else
            record = Execution.create!(
              idempotency_key: idempotency_key,
              serialized_job: serialized_job,
              definition: definition,
              recover_to: definition.keys.first
            )
          end

          record
        end
      end

      def take_step(step_definition)
        if step_definition["if"]
          unless resolve_method(step_definition["if"]).call
            @execution.record!(step: step_definition["does"], action: :skipped, timestamp: Time.now)
            return
          end
        elsif step_definition["unless"]
          if resolve_method(step_definition["unless"]).call
            @execution.record!(step: step_definition["does"], action: :skipped, timestamp: Time.now)
            return
          end
        end

        step_method = step_definition["does"]

        if @execution.entries.exists?(step: step_method, action: :succeeded)
          raise SucceededStepError, step_method
        end

        current_entries = @execution.entries.where(step: step_method).group(:action).having(action: [:started, :iterated]).count.symbolize_keys!
        if current_entries == { started: 1, iterated: 0 }
          if step_definition["idempotency_check"].present?
            if resolve_method(step_definition["idempotency_check"]).call
              @execution.record!(step: step_method, action: :skipped, timestamp: Time.now)
              return true
            else
              @execution.record!(step: step_method, action: :retried, timestamp: Time.now)
            end
          else
            @execution.record!(step: step_method, action: :retried, timestamp: Time.now)
          end
        elsif current_entries in { started: 1, iterated: Integer }
          # no-op, we've already started this step
        else
          @execution.record!(step: step_method, action: :started, timestamp: Time.now)
        end

        current_callable = if respond_to?(step_method, _include_private = true)
            method(step_method)
          elsif step_definition["awaits"].present?
            # jobs can have no-op steps if they use the async/await mechanism for that step
            proc {}
          else
            raise UndefinedMethodError, step_method
          end

        rescued_error = nil
        begin
          wrapper = if step_definition["transactional"]
              @execution.method(:with_lock)
            else
              proc { |&block| block.call }
            end

          iterating = step_definition["for_each"].present?
          if iterating
            current_cursor = @execution.recover_to_cursor
            object, next_cursor = resolve_object_and_next_cursor(from: step_definition["for_each"], at: current_cursor)

            if object.present?
              wrapper.call { current_callable.call(object) }
              @execution.record!(step: step_method, action: :iterated, timestamp: Time.now, cursor: next_cursor)

              return "#{step_method}:#{next_cursor}"

            # have iterated over all items
            elsif object.nil?
              @execution.record!(step: step_method, action: :completed, timestamp: Time.now)

              return step_definition.fetch("then")
            else
              raise "Unknown iteration error: #{object.inspect}"
            end
          elsif current_callable.arity.zero?
            wrapper.call { current_callable.call }

            @execution.record!(step: step_method, action: :succeeded, timestamp: Time.now)

            return step_definition.fetch("then")

          else
            raise "TooManyParametersForStepMethod"
          end
        rescue StandardError => e
          if step_definition.dig("compensate", "on").present? && Array(step_definition.dig("compensate", "on")).any? { |klass| e.is_a?(klass) }
            compensate_method = step_definition.dig("compensate", "with")
            if respond_to?(compensate_method, _include_private = true)
              method(compensate_method).call
              @execution.record!(step: step_method, action: :compensated, timestamp: Time.now)
            else
              raise UndefinedCompensateMethod.new("Undefined compensate method: #{compensate_method}")
            end
          else
            rescued_error = e
            raise e
          end
        ensure
          if rescued_error
            begin
              @execution.record!(step: step_method, action: :errored, timestamp: Time.now, exception_class: rescued_error.class.name, message: rescued_error.message)
            rescue StandardError => e
              # We're already inside an error condition, so swallow any additional
              # errors from here and just send them to logs.
              Logger.error("Failed to store exception for workflow #{@execution.id} because of #{e}.")
            end
          end
        end
      end

      def awaited_jobs_for(step_definition)
        collection = case (jobs_or_jobs_getter = step_definition["awaits"])
          when Array
            jobs_or_jobs_getter.compact
          when Symbol, String
            if respond_to?(jobs_or_jobs_getter, _include_private = true)
              jobs = method(jobs_or_jobs_getter).call
              Array(jobs).compact
            else
              raise InvalidStepError, "Invalid `awaits`; unknown method `#{jobs_or_jobs_getter}` for this job"
            end
          when nil
            []
          else
            raise InvalidStepError, "Invalid `awaits`; must be either an jobs Array or method name, was: #{jobs_or_jobs_getter.class.name}"
          end

        collection.map do |item|
          job, args = Class === item ? [item, []] : [item.class, item.arguments]
          job.new(*args)
        end
      end

      def resolve_object_and_next_cursor(from:, at: nil)
        iterable, cursor_position = from, at

        enumerable_to_enumerator = proc do |enumerable|
          drop = cursor_position.nil? ? 0 : cursor_position + 1
          enumerable.each_with_index.drop(drop).to_enum { enumerable.size }
        end

        ensure_enumerator = proc do |iterable|
          case iterable
          when Enumerable
            enumerable_to_enumerator.call(iterable)
          when Enumerator
            iterable
          else
            raise ArgumentError, "for_each: must return an Enumerable or Enumerator, was: #{iterable.class}"
          end
        end

        enumerator = case iterable
          when Enumerable
            enumerable_to_enumerator.call(iterable)
          when Symbol, String
            if respond_to?(iterable, _include_private = true)
              iterable_method = method(iterable)
              if iterable_method.arity.zero?
                iterable_result = iterable_method.call
                ensure_enumerator.call(iterable_result)
              elsif iterable_method.arity == 1 && iterable_method.parameters.first == [:keyreq, :cursor]
                iterable_result = iterable_method.call(cursor: cursor_position)
                ensure_enumerator.call(iterable_result)
              else
                raise ArgumentError, "for_each: must be a 0-arity or 1-arity method"
              end
            elsif (iterable_result = @ctx[iterable]).present?
              ensure_enumerator.call(iterable_result)
            end
          else
            raise ArgumentError, "for_each: must be an Enumerable, Symbol, or String"
          end

        begin
          enumerator.next
        rescue StopIteration
          [nil, nil]
        end
      end

      def resolve_method(name)
        raise UndefinedMethodError if not respond_to?(name, _include_private = true)

        method(name)
      end
  end
end
