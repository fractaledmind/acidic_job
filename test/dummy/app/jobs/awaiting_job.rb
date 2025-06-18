class AwaitingJob < ApplicationJob
  include AcidicJob::Workflow

  def perform
    execute_workflow(unique_by: job_id) do |w|
      w.step :enqueue_jobs
      w.step :await_jobs
      w.step :do_something
    end
  end

  def enqueue_jobs
    awaited_job_1 = ctx.fetch(:awaited_job_1) { AwaitedJob.new(execution) }
    awaited_job_2 = ctx.fetch(:awaited_job_2) { AwaitedJob.new(execution) }

    return if ctx[awaited_job_1.job_id] || ctx[awaited_job_2.job_id]

    ctx[:job_ids] = [awaited_job_1.job_id, awaited_job_2.job_id]

    ActiveJob.perform_all_later(awaited_job_1, awaited_job_2)
  end

  def await_jobs
    ctx[:job_ids].each do |job_id|
      halt_workflow! unless ctx[job_id]
    end
  end

  def do_something
    # idempotent because journal logging is idempotent via Set
    # but this means data logged must be identical across executions
    ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
  end
end