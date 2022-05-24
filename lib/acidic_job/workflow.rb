# frozen_string_literal: true

module AcidicJob
  class Workflow
    # { "step 1": { does: "step 1", awaits: [], then: "step 2" }, ...  }
    def initialize(run, job, step_result = nil)
      @run = run
      @job = job
      @step_result = step_result
      @workflow_hash = @run.workflow
    end

    def execute_current_step
      rescued_error = false

      begin
        run_current_step
      rescue StandardError => e
        rescued_error = e
        raise e
      ensure
        if rescued_error
          begin
            @run.update_columns(locked_at: nil, error_object: rescued_error)
          rescue StandardError => e
            # We're already inside an error condition, so swallow any additional
            # errors from here and just send them to logs.
            AcidicJob.logger.error("Failed to unlock AcidicJob::Run #{@run.id} because of #{e}.")
          end
        end
      end

      # be sure to return the `step_result` from running the (wrapped) current step method
      @step_result
    end

    def progress_to_next_step
      return if current_step_finished?
      return run_step_result unless next_step_finishes?

      @job.run_callbacks :finish do
        run_step_result
      end
    end

    def current_step_name
      @run.recovery_point
    end

    def current_step_hash
      @workflow_hash[current_step_name]
    end

    private

    def run_current_step
      wrapped_method = wrapped_current_step_method

      AcidicJob.logger.log_run_event("Executing #{current_step_name}...", @job, @run)
      @run.with_lock do
        @step_result = wrapped_method.call(@run)
      end
      AcidicJob.logger.log_run_event("Executed #{current_step_name}.", @job, @run)
    end

    def run_step_result
      next_step = next_step_name
      AcidicJob.logger.log_run_event("Progressing to #{next_step}...", @job, @run)
      @run.with_lock do
        @step_result.call(run: @run)
      end
      AcidicJob.logger.log_run_event("Progressed to #{next_step}.", @job, @run)
    end

    def next_step_name
      current_step_hash&.fetch("then")
    end

    def next_step_finishes?
      next_step_name.to_s == Run::FINISHED_RECOVERY_POINT
    end
    
    def current_step_finished?
      current_step_name.to_s == Run::FINISHED_RECOVERY_POINT
    end

    def wrapped_current_step_method
      # return a callable Proc with a consistent interface for the execution phase
      proc do |_run|
        callable = current_step_method

        # STEP ITERATION
        # the `iterable_key` represents the name of the collection accessor
        # that must be present in `@run.attr_accessors`; that is,
        # it must have been passed to `providing` when calling `with_acidity`
        iterable_key = current_step_hash["for_each"]
        raise UnknownForEachCollection if iterable_key.present? && !@run.attr_accessors.key?(iterable_key)

        # in order to ensure we don't iterate over successfully iterated values in previous runs,
        # we need to store the collection of already processed values.
        # we store this collection under a key bound to the current step to ensure multiple steps
        # can iterate over the same collection.
        iterated_key = "processed_#{current_step_name}_#{iterable_key}"

        # Get the collection of values to iterate over (`prev_iterables`)
        # and the collection of values already iterated (`prev_iterateds`)
        # in order to determine the collection of values to iterate over (`curr_iterables`)
        prev_iterables = @run.attr_accessors.fetch(iterable_key, []) || []
        raise UniterableForEachCollection unless prev_iterables.is_a?(Enumerable)

        prev_iterateds = @run.attr_accessors.fetch(iterated_key, []) || []
        curr_iterables = prev_iterables.reject { |item| prev_iterateds.include? item }
        next_item = curr_iterables.first

        result = nil
        if iterable_key.present? && next_item.present? # have an item to iterate over, so pass it to the step method
          result = callable.call(next_item)
        elsif iterable_key.present? && next_item.nil? # have iterated over all items
          result = true
        elsif callable.arity.zero?
          result = callable.call
        else
          raise TooManyParametersForStepMethod
        end

        if result.is_a?(FinishedPoint)
          result
        elsif next_item.present?
          prev_iterateds << next_item
          @run.attr_accessors[iterated_key] = prev_iterateds
          @run.save!(validate: false)
          RecoveryPoint.new(current_step_name)
        elsif next_step_finishes?
          FinishedPoint.new
        else
          RecoveryPoint.new(next_step_name)
        end
      end
    end

    # jobs can have no-op steps, especially so that they can use only the async/await mechanism for that step
    def current_step_method
      return @job.method(current_step_name) if @job.respond_to?(current_step_name, _include_private = true)
      return proc {} if current_step_hash["awaits"].present?

      raise UndefinedStepMethod
    end
  end
end
