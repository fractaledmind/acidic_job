class EnqueuingJob < ApplicationJob
  include AcidicJob::Workflow

  def perform
    execute_workflow(unique_by: job_id) do |w|
      w.step :enqueue_job
      w.step :do_something
    end
  end

  def enqueue_job
    child_job = ctx.fetch(:child_job) { EnqueuedJob.new(execution) }

    return if ctx[child_job.job_id]

    ActiveJob.perform_all_later(child_job)
  end

  def do_something
    # idempotent because journal logging is idempotent via Set
    # but this means data logged must be identical across executions
    ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
  end
end