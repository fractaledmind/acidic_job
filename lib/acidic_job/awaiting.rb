# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module Awaiting
    extend ActiveSupport::Concern

    private

    def enqueue_step_parallel_jobs(jobs, run, step_result)
      # `batch` is available from Sidekiq::Pro
      raise SidekiqBatchRequired unless defined?(Sidekiq::Batch)

      step_batch = Sidekiq::Batch.new
      # step_batch.description = "AcidicJob::Workflow Step: #{step}"
      step_batch.on(
        :success,
        "#{self.class.name}#step_done",
        # NOTE: options are marshalled through JSON so use only basic types.
        {
          "run_id" => run.id,
          "step_result_yaml" => step_result.to_yaml.strip,
          "parent_worker" => self.class.name,
          "job_names" => jobs.map { |job| job_name(job) }
        }
      )

      # NOTE: The jobs method is atomic.
      # All jobs created in the block are actually pushed atomically at the end of the block.
      # If an error is raised, none of the jobs will go to Redis.
      step_batch.jobs do
        jobs.each do |job|
          worker, args, kwargs = job_args_and_kwargs(job)

          worker.perform_async(*args, **kwargs)
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

    def job_name(job)
      case job
      when Class, Symbol
        job.to_s
      when String
        job
      else
        job.class.name
      end
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
