# frozen_string_literal: true

require "active_job"

module AcidicJob
  module Workflow
    REPEAT_STEP = :__ACIDIC_JOB_REPEAT_STEP_SIGNAL__
    HALT_STEP = :__ACIDIC_JOB_HALT_STEP_SIGNAL__
    private_constant :REPEAT_STEP, :HALT_STEP

    def execute_workflow(unique_by:, with: AcidicJob.plugins, &block)
      @__acidic_job_plugins__ = with
      serialized_job = serialize

      workflow_definition = AcidicJob.instrument(:define_workflow, **serialized_job) do
        raise RedefiningWorkflowError if defined? @__acidic_job_builder__

        @__acidic_job_builder__ = Builder.new(@__acidic_job_plugins__)

        raise UndefinedWorkflowBlockError unless block_given?
        raise InvalidWorkflowBlockError if block.arity != 1

        block.call @__acidic_job_builder__

        raise MissingStepsError if @__acidic_job_builder__.steps.empty?

        # convert the array of steps into a hash of recovery_points and next steps
        @__acidic_job_builder__.define_workflow
      end

      AcidicJob.instrument(:initialize_workflow, definition: workflow_definition) do
        transaction_args = case ::ActiveRecord::Base.connection.adapter_name.downcase.to_sym
          # SQLite doesn't support `serializable` transactions
          when :sqlite
            {}
          else
            { isolation: :serializable }
        end
        idempotency_key = Digest::SHA256.hexdigest(JSON.fast_generate([self.class.name, unique_by], strict: true))

        @__acidic_job_execution__ = ::ActiveRecord::Base.transaction(**transaction_args) do
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
            starting_point = if workflow_definition.key?("steps")
              workflow_definition["steps"].keys.first
            else
              # TODO: add deprecation warning
              workflow_definition.keys.first
            end

            record = Execution.create!(
              idempotency_key: idempotency_key,
              serialized_job: serialized_job,
              definition: workflow_definition,
              recover_to: starting_point
            )
          end

          record
        end
      end
      @__acidic_job_context__ ||= Context.new(@__acidic_job_execution__)

      AcidicJob.instrument(:process_workflow, execution: @__acidic_job_execution__.attributes) do
        # if the workflow record is already marked as finished, immediately return its result
        return true if @__acidic_job_execution__.finished?

        loop do
          break if @__acidic_job_execution__.finished?

          current_step = @__acidic_job_execution__.recover_to

          if not @__acidic_job_execution__.defined?(current_step)
            raise UndefinedStepError.new(current_step)
          end

          step_definition = @__acidic_job_execution__.definition_for(current_step)
          AcidicJob.instrument(:process_step, **step_definition) do
            recover_to = catch(:halt) { take_step(step_definition) }
            case recover_to
            when HALT_STEP
              @__acidic_job_execution__.record!(
                step: step_definition.fetch("does"),
                action: :halted,
              )
              return true
            else
              @__acidic_job_execution__.update_column(:recover_to, recover_to)
            end
          end
        end
      end
    end

    def repeat_step!
      throw :repeat, REPEAT_STEP
    end

    def halt_workflow!
      throw :halt, HALT_STEP
    end

    def halt_step!
      # TODO add deprecation warning
      halt_workflow!
    end

    def step_retrying?
      step_name = caller_locations.first.label

      if not @__acidic_job_execution__.defined?(step_name)
        raise UndefinedStepError.new(step_name)
      end

      @__acidic_job_execution__.entries.where(step: step_name, action: "started").count > 1
    end

    def execution
      @__acidic_job_execution__
    end

    def ctx
      @__acidic_job_context__
    end

    private def take_step(step_definition)
      curr_step = step_definition.fetch("does")
      next_step = step_definition.fetch("then")

      return next_step if @__acidic_job_execution__.entries.exists?(step: curr_step, action: :succeeded)

      rescued_error = nil
      begin
        @__acidic_job_execution__.record!(step: curr_step, action: :started)
        result = AcidicJob.instrument(:perform_step, **step_definition) do
          perform_step_for(step_definition)
        end
        case result
        when REPEAT_STEP
          curr_step
        else
          @__acidic_job_execution__.record!(
            step: curr_step,
            action: :succeeded,
            ignored: {
              result: result,
            }
          )
          next_step
        end
      rescue => e
        rescued_error = e
        raise e
      ensure
        if rescued_error
          begin
            @__acidic_job_execution__.record!(
              step: curr_step,
              action: :errored,
              exception_class: rescued_error.class.name,
              message: rescued_error.message
            )
          rescue => e
            # We're already inside an error condition, so swallow any additional
            # errors from here and just send them to logs.
            logger.error(
              "Failed to store exception at step #{curr_step} for execution ##{@__acidic_job_execution__.id}: #{e}."
            )
          end
        end
      end
    end

    private def perform_step_for(step_definition)
      step_name = step_definition.fetch("does")
      begin
        step_method = method(step_name)
      rescue NameError
        raise UndefinedMethodError.new(step_name)
      end

      # raise InvalidMethodError.new(step_name) unless step_method.arity.zero?

      plugin_pipeline_callable = @__acidic_job_plugins__.reverse.reduce(step_method) do |callable, plugin|
        context = PluginContext.new(plugin, self, @__acidic_job_execution__, @__acidic_job_context__, step_definition)

        if context.inactive?
          callable
        else
          proc do
            called = false

            result = plugin.around_step(context) do |*args, **kwargs|
              raise DoublePluginCallError.new(plugin, step_name) if called

              called = true

              if callable.arity.zero?
                callable.call
              else
                callable.call(*args, **kwargs)
              end
            end

            # raise MissingPluginCallError.new(plugin, step_name) unless called

            result
          end
        end
      end

      catch(:repeat) { plugin_pipeline_callable.call }
    end
  end
end
