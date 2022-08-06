# frozen_string_literal: true

module AcidicJob
  class Workflow
    # { "step 1": { does: "step 1", awaits: [], then: "step 2" }, ...  }
    def initialize(run, job, step_result = nil)
      @run = run
      @job = job
      @step_result = step_result
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
            @run.store_error!(rescued_error)
          rescue StandardError => e
            # We're already inside an error condition, so swallow any additional
            # errors from here and just send them to logs.
            AcidicJob.logger.error("Failed to unlock AcidicJob::Run #{@run.id} because of #{e}.")
          end
        end
      end

      # be sure to return the `step_result`
      # which is set by `run_current_step`
      # which runs the (wrapped) current step method
      @step_result
    end

    def progress_to_next_step
      return if @run.current_step_finished?
      return run_step_result unless @run.next_step_finishes?

      @job.run_callbacks :finish do
        run_step_result
      end
    end

    private

    def run_current_step
      wrapped_method = WorkflowStep.new(run: @run, job: @job).wrapped
      current_step = @run.current_step_name

      # can't reproduce yet, but saw a bug in production where
      # nested awaits workflows had an unsaved `workflow` attribute
      @run.save! if @run.has_changes_to_save?

      AcidicJob.logger.log_run_event("Executing #{current_step}...", @job, @run)
      @run.with_lock do
        @step_result = wrapped_method.call(@run)
      end
      AcidicJob.logger.log_run_event("Executed #{current_step}.", @job, @run)
    end

    def run_step_result
      next_step = @run.next_step_name

      # can't reproduce yet, but saw a bug in production where
      # nested awaits workflows had an unsaved `workflow` attribute
      @run.save! if @run.has_changes_to_save?

      AcidicJob.logger.log_run_event("Progressing to #{next_step}...", @job, @run)
      @run.with_lock do
        @step_result.call(run: @run)
      end
      AcidicJob.logger.log_run_event("Progressed to #{next_step}.", @job, @run)
    end
  end
end
