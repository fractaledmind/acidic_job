# frozen_string_literal: true

require "active_job"

module AcidicJob
  module Workflow
    NO_OP_WRAPPER = proc { |&block| block.call }
    REPEAT_STEP = :REPEAT_STEP
    HALT_STEP = :HALT_STEP

    # PUBLIC
    # provide a default mechanism for identifying unique job runs
    # typical: [self.class.name, self.arguments]
    def unique_by
      job_id
    end

    # PUBLIC
    def execute_workflow(&block)
      serialized_job = serialize

      AcidicJob.instrument(:define_workflow, **serialized_job) do
        raise RedefiningWorkflowError if defined? @builder

        @builder = Builder.new

        raise UndefinedWorkflowBlockError unless block_given?
        raise InvalidWorkflowBlockError if block.arity != 1

        block.call @builder

        raise MissingStepsError if @builder.steps.empty?

        # convert the array of steps into a hash of recovery_points and next steps
        @workflow_definition = @builder.define_workflow
      end

      AcidicJob.instrument(:initialize_workflow, "definition" => @workflow_definition) do
        transaction_args = case ::ActiveRecord::Base.connection.adapter_name.downcase.to_sym
                           # SQLite doesn't support `serializable` transactions
                           when :sqlite
                             {}
                           else
                             { isolation: :serializable }
                           end

        @execution = ::ActiveRecord::Base.transaction(**transaction_args) do
          record = Execution.find_by(idempotency_key: idempotency_key)

          if record.present?
            # Programs enqueuing multiple jobs with different parameters but the
            # same idempotency key is a bug.
            if record.raw_arguments != serialized_job["arguments"]
              raise ArgumentMismatchError.new(serialized_job["arguments"], record.raw_arguments)
            end

            if record.definition != @workflow_definition
              raise DefinitionMismatchError.new(@workflow_definition, record.definition)
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
              definition: @workflow_definition,
              recover_to: @workflow_definition.keys.first
            )
          end

          record
        end
      end
      @ctx ||= Context.new(@execution)

      AcidicJob.instrument(:process_workflow, execution: @execution.attributes) do
        # if the workflow record is already marked as finished, immediately return its result
        return true if @execution.finished?

        loop do
          break if @execution.finished?

          current_step = @execution.recover_to

          if not @execution.definition.key?(current_step) # rubocop:disable Style/Not
            raise UndefinedStepError.new(current_step)
          end

          step_definition = @execution.definition[current_step]
          AcidicJob.instrument(:process_step, **step_definition) do
            recover_to = catch(:halt) { take_step(step_definition) }
            case recover_to
            when HALT_STEP
              @execution.record!(step: step_definition.fetch("does"), action: :halted, timestamp: Time.now)
              return true
            else
              @execution.update!(recover_to: recover_to)
            end
          end
        end
      end
    end

    # PRIVATE
    def take_step(step_definition)
      curr_step = step_definition.fetch("does")
      next_step = step_definition.fetch("then")

      return next_step if @execution.entries.exists?(step: curr_step, action: :succeeded)

      step_method = performable_step_for(step_definition)
      rescued_error = nil
      begin
        @execution.record!(step: curr_step, action: :started, timestamp: Time.now)
        result = AcidicJob.instrument(:perform_step, **step_definition) do
          step_method.call
        end
        case result
        when REPEAT_STEP
          curr_step
        else
          @execution.record!(step: curr_step, action: :succeeded, timestamp: Time.now, result: result)
          next_step
        end
      rescue StandardError => e
        rescued_error = e
        raise e
      ensure
        if rescued_error
          begin
            @execution.record!(
              step: curr_step,
              action: :errored,
              timestamp: Time.now,
              exception_class: rescued_error.class.name,
              message: rescued_error.message
            )
          rescue StandardError => e
            # We're already inside an error condition, so swallow any additional
            # errors from here and just send them to logs.
            logger.error(
              "Failed to store exception at step #{curr_step} for execution ##{@execution.id} because of #{e}."
            )
          end
        end
      end
    end

    # PRIVATE
    # encode the job run identifier as a hex string
    def idempotency_key
      @idempotency_key ||= Digest::SHA256.hexdigest(JSON.dump(unique_by))
    end

    # PRIVATE
    def performable_step_for(step_definition)
      step_name = step_definition.fetch("does")
      step_method = method(step_name)

      raise InvalidMethodError.new(step_name) unless step_method.arity.zero?

      wrapper = step_definition["transactional"] ? @execution.method(:with_lock) : NO_OP_WRAPPER

      proc do
        catch(:repeat) { wrapper.call { step_method.call } }
      end
    rescue NameError
      raise UndefinedMethodError.new(step_name)
    end

    # PUBLIC
    def repeat_step!
      throw :repeat, REPEAT_STEP
    end

    def halt_step!
      throw :halt, HALT_STEP
    end
  end
end
