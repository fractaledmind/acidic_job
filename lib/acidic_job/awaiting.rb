# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module Awaiting
    extend ActiveSupport::Concern

    class_methods do
      # TODO: Allow the `perform` method to be used to kick off Sidekiq Batch powered workflows
      def initiate(*args)
        raise SidekiqBatchRequired unless defined?(Sidekiq::Batch)

        top_level_workflow = Sidekiq::Batch.new
        top_level_workflow.on(:success, self, *args)
        top_level_workflow.jobs do
          perform_async
        end
      end
    end

    def enqueue_step_parallel_jobs(jobs, run, step_result)
      # `batch` is available from Sidekiq::Pro
      raise SidekiqBatchRequired unless defined?(Sidekiq::Batch)

      batch.jobs do
        step_batch = Sidekiq::Batch.new
        # step_batch.description = "AcidicJob::Workflow Step: #{step}"
        step_batch.on(
          :success,
          "#{self.class.name}#step_done",
          # NOTE: options are marshalled through JSON so use only basic types.
          { "run_id" => run.id,
            "step_result_yaml" => step_result.to_yaml.strip }
        )
        # NOTE: The jobs method is atomic.
        # All jobs created in the block are actually pushed atomically at the end of the block.
        # If an error is raised, none of the jobs will go to Redis.
        step_batch.jobs do
          jobs.each do |worker_name|
            # TODO: handle Symbols as well
            worker = worker_name.is_a?(String) ? worker_name.constantize : worker_name
            if worker.instance_method(:perform).arity.zero?
              worker.perform_async
            elsif worker.instance_method(:perform).arity == 1
              worker.perform_async(run.id)
            else
              raise TooManyParametersForParallelJob
            end
          end
        end
      end
    end

    def step_done(_status, options)
      run = Run.find(options["run_id"])
      current_step = run.workflow[run.recovery_point.to_s]
      # re-hydrate the `step_result` object
      step_result = YAML.load(options["step_result_yaml"])
      step = Step.new(current_step, run, self, step_result)

      # TODO: WRITE REGRESSION TESTS FOR PARALLEL JOB FAILING AND RETRYING THE ORIGINAL STEP
      step.progress
      # when a batch of jobs for a step succeeds, we begin processing the `AcidicJob::Run` record again
      process_run(run)
    end
  end
end
