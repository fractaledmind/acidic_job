# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module Awaiting
    extend ActiveSupport::Concern

    private

    def was_awaited_job?
      (acidic_job_run.present? && acidic_job_run.awaited_by.present?) ||
        (staged_job_run.present? && staged_job_run.awaited_by.present?)
    end

    def reenqueue_awaited_by_job
      run = staged_job_run&.awaited_by || acidic_job_run&.awaited_by

      return unless run
      return if run.batched_runs.outstanding.any?

      current_step = run.workflow[run.recovery_point.to_s]
      step_result = run.returning_to

      job = run.job_class.constantize.deserialize(run.serialized_job)
      # this needs to be explicitly set so that `was_workflow_job?` appropriately returns `true`
      # which is what the `after_finish :reenqueue_awaited_by_job` check needs
      job.instance_variable_set(:@acidic_job_run, run)

      step = Step.new(current_step, run, job, step_result)
      # TODO: WRITE REGRESSION TESTS FOR PARALLEL JOB FAILING AND RETRYING THE ORIGINAL STEP
      step.progress

      return if run.finished?

      # when a batch of jobs for a step succeeds, we begin processing the `AcidicJob::Run` record again
      # process_run(run)
      run.update_column(:locked_at, nil)
      job.enqueue
    end

    def enqueue_step_parallel_jobs(jobs_or_jobs_getter, run, step_result)
      awaited_jobs = case jobs_or_jobs_getter
                     when Array
                       jobs_or_jobs_getter
                     when Symbol, String
                       method(jobs_or_jobs_getter).call
                     end

      AcidicJob::Run.transaction do
        awaited_jobs.each do |awaited_job|
          worker_class, args, kwargs = job_args_and_kwargs(awaited_job)

          job = worker_class.new(*args, **kwargs)

          AcidicJob::Run.create!(
            staged: true,
            awaited_by: run,
            job_class: worker_class,
            serialized_job: job.serialize_job(*args, **kwargs),
            idempotency_key: job.idempotency_key
          )
          run.update(returning_to: step_result)
        end
      end
    end

    def step_done(_status, options)
      run = Run.find(options["run_id"])
      current_step = run.workflow[run.recovery_point.to_s]
      # re-hydrate the `step_result` object
      step_result = YAML.safe_load(options["step_result_yaml"], permitted_classes: [RecoveryPoint, FinishedPoint])
      step = Step.new(current_step, run, self, step_result)

      # TODO: WRITE REGRESSION TESTS FOR PARALLEL JOB FAILING AND RETRYING THE ORIGINAL STEP
      step.progress
      # when a batch of jobs for a step succeeds, we begin processing the `AcidicJob::Run` record again
      process_run(run)
    end

    def job_args_and_kwargs(job)
      case job
      when Class
        [job, [], {}]
      when String
        [job.constantize, [], {}]
      when Symbol
        [job.to_s.constantize, [], {}]
      else
        [
          job.class,
          job.instance_variable_get(:@__acidic_job_args),
          job.instance_variable_get(:@__acidic_job_kwargs)
        ]
      end
    end
  end
end
