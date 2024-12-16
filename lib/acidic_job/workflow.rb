# frozen_string_literal: true

require "active_job"

module AcidicJob
  module Workflow
    NO_OP_WRAPPER = proc { |&block| block.call }
    REPEAT_STEP = :REPEAT_STEP
    HALT_STEP = :HALT_STEP
    private_constant :NO_OP_WRAPPER, :REPEAT_STEP, :HALT_STEP

    attr_reader :execution, :ctx

    def execute_workflow(unique_by:, with: [], &block)
      @plugins = with
      serialized_job = serialize

      workflow_definition = AcidicJob.instrument(:define_workflow, **serialized_job) do
        raise RedefiningWorkflowError if defined? @_builder

        @_builder = Builder.new(@plugins)

        raise UndefinedWorkflowBlockError unless block_given?
        raise InvalidWorkflowBlockError if block.arity != 1

        block.call @_builder

        raise MissingStepsError if @_builder.steps.empty?

        # convert the array of steps into a hash of recovery_points and next steps
        @_builder.define_workflow
      end

      AcidicJob.instrument(:initialize_workflow, "definition" => workflow_definition) do
        transaction_args = case ::ActiveRecord::Base.connection.adapter_name.downcase.to_sym
                           # SQLite doesn't support `serializable` transactions
                           when :sqlite
                             {}
                           else
                             { isolation: :serializable }
                           end
        idempotency_key = Digest::SHA256.hexdigest(JSON.dump([self.class.name, unique_by]))

        @execution = ::ActiveRecord::Base.transaction(**transaction_args) do
          record = Execution.find_by(idempotency_key: idempotency_key)

          if record.present?
            # Programs enqueuing multiple jobs with different parameters but the
            # same idempotency key is a bug.
            if record.raw_arguments != serialized_job["arguments"]
              raise ArgumentMismatchError.new(serialized_job["arguments"], record.raw_arguments)
            end

            if record.definition != workflow_definition
              raise DefinitionMismatchError.new(workflow_definition, record.definition)
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
              definition: workflow_definition,
              recover_to: workflow_definition.keys.first
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

    def repeat_step!
      throw :repeat, REPEAT_STEP
    end

    def halt_step!
      throw :halt, HALT_STEP
    end

    def step_retrying?
      step_name = caller_locations.first.label

      if not @execution.definition.key?(step_name) # rubocop:disable Style/IfUnlessModifier, Style/Not
        raise UndefinedStepError.new(step_name)
      end

      @execution.entries.where(step: step_name, action: "started").count > 1
    end

    private

    def take_step(step_definition)
      curr_step = step_definition.fetch("does")
      next_step = step_definition.fetch("then")

      return next_step if @execution.entries.exists?(step: curr_step, action: :succeeded)

      rescued_error = nil
      begin
        @execution.record!(step: curr_step, action: :started, timestamp: Time.now)
        result = AcidicJob.instrument(:perform_step, **step_definition) do
          perform_step_for(step_definition)
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

    def perform_step_for(step_definition)
      step_name = step_definition.fetch("does")
      step_method = method(step_name)

      raise InvalidMethodError.new(step_name) unless step_method.arity.zero?

      wrapper = step_definition["transactional"] ? @execution.method(:with_lock) : NO_OP_WRAPPER

      catch(:repeat) { wrapper.call { step_method.call } }
    rescue NameError
      raise UndefinedMethodError.new(step_name)
    end
  end
end
