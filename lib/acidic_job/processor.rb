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

      AcidicJob.logger.debug("Processing #{@job.class.name}:#{@job.object_id} -> #{@workflow.current_step_name} (Run ID: #{@run.idempotency_key})...")

      loop do
        if @run.finished?
          break
        elsif !@run.known_recovery_point?
          raise UnknownRecoveryPoint,
                "Defined workflow does not reference this step: #{@workflow.current_step_name.inspect}"
        elsif !(awaited_jobs = @workflow.current_step_hash.fetch("awaits", []) || []).empty?
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
          break
        else
          @workflow.execute_current_step
          @workflow.progress_to_next_step
        end
      end
      AcidicJob.logger.debug("Processed #{@job.class.name}:#{@job.object_id} -> #{@workflow.current_step_name} (Run ID: #{@run.idempotency_key}).")

      @run.succeeded?
    end

    private

    def enqueue_awaited_jobs(jobs_or_jobs_getter, step_result)
      awaited_jobs = jobs_from(jobs_or_jobs_getter)

      AcidicJob.logger.debug("Enqueuing #{awaited_jobs.count} jobs awaited by #{@job.class.name}:#{@job.object_id} -> #{@workflow.current_step_name} (Run ID: #{@run.idempotency_key})...")

      # All jobs created in the block are actually pushed atomically at the end of the block.
      AcidicJob::Run.transaction do
        awaited_jobs.each do |awaited_job|
          worker_class, args, kwargs = job_args_and_kwargs(awaited_job)

          job = worker_class.new(*args, **kwargs)

          AcidicJob::Run.create!(
            staged: true,
            awaited_by: @run,
            returning_to: step_result,
            job_class: worker_class,
            serialized_job: job.serialize,
            idempotency_key: IdempotencyKey.new(job).value(acidic_by: worker_class.try(:acidic_identifier))
          )
        end
      end

      AcidicJob.logger.debug("Enqueued #{awaited_jobs.count} jobs awaited by #{@job.class.name}:#{@job.object_id} -> #{@workflow.current_step_name} (Run ID: #{@run.idempotency_key}).")
    end

    def jobs_from(jobs_or_jobs_getter)
      case jobs_or_jobs_getter
      when Array
        jobs_or_jobs_getter
      when Symbol, String
        @job.method(jobs_or_jobs_getter).call
      else
        raise UnknownAwaitedJob,
              "Option passed to `awaits` is invalid; must be either an Array of jobs or a method name, was: #{jobs_or_jobs_getter.class.name}"
      end
    end

    def job_args_and_kwargs(job)
      case job
      when Class
        [job, [], {}]
      else
        [
          job.class,
          job.arguments,
          {}
        ]
      end
    end
  end
end
