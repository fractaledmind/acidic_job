# frozen_string_literal: true

module AcidicJob
  class Processor
    def initialize(run, job)
      @run = run
      @job = job
      @workflow = Workflow.new(run, job)
    end

    def process_run
      # if the run record is already marked as finished, immediately return its result
      return @run.succeeded? if @run.finished?

      AcidicJob.logger.log_run_event("Processing #{@run.current_step_name}...", @job, @run)
      loop do
        break if @run.finished?

        if !@run.known_recovery_point?
          raise UnknownRecoveryPoint,
                "Defined workflow does not reference this step: #{@run.current_step_name.inspect}"
        elsif (awaited_jobs = jobs_from(@run.current_step_awaits)).any?
          # We only execute the current step, without progressing to the next step.
          # This ensures that any failures in parallel jobs will have this step retried in the main workflow
          step_result = @workflow.execute_current_step
          # We allow the `#step_done` method to manage progressing the recovery_point to the next step,
          # and then calling `process_run` to restart the main workflow on the next step.
          # We pass the `step_result` so that the async callback called after the step-parallel-jobs complete
          # can move on to the appropriate next stage in the workflow.
          enqueue_awaited_jobs(awaited_jobs, step_result)
          # after processing the current step, break the processing loop
          # and stop this method from blocking in the primary worker
          # as it will continue once the background workers all succeed
          # so we want to keep the primary worker queue free to process new work
          # this CANNOT ever be `break` as that wouldn't exit the parent job,
          # only this step in the workflow, blocking as it awaits the next step
          return true
        else
          @workflow.execute_current_step
          @workflow.progress_to_next_step
        end
      end
      AcidicJob.logger.log_run_event("Processed #{@run.current_step_name}.", @job, @run)

      @run.succeeded?
    end

    private

    def enqueue_awaited_jobs(awaited_jobs, step_result)
      AcidicJob.logger.log_run_event("Enqueuing #{awaited_jobs.count} awaited jobs...", @job, @run)
      # All jobs created in the block are pushed atomically at the end of the block.
      AcidicJob::Run.transaction do
        awaited_jobs.each do |awaited_job|
          worker_class, args = job_and_args(awaited_job)

          job = worker_class.new(*args)

          AcidicJob::Run.await!(job, by: @run, return_to: step_result)
        end
      end
      AcidicJob.logger.log_run_event("Enqueued #{awaited_jobs.count} awaited jobs.", @job, @run)
    end

    def jobs_from(jobs_or_jobs_getter)
      case jobs_or_jobs_getter
      when Array
        jobs_or_jobs_getter.compact
      when Symbol, String
        if @job.respond_to?(jobs_or_jobs_getter, _include_private = true)
          jobs = @job.method(jobs_or_jobs_getter).call
          Array(jobs).compact
        else
          raise UnknownAwaitedJob,
                "Invalid `awaits`; unknown method `#{jobs_or_jobs_getter}` for this job"
        end
      else
        raise UnknownAwaitedJob,
              "Invalid `awaits`; must be either an jobs Array or method name, was: #{jobs_or_jobs_getter.class.name}"
      end
    end

    def job_and_args(job)
      case job
      when Class
        [job, []]
      else
        [
          job.class,
          job.arguments
        ]
      end
    end
  end
end
