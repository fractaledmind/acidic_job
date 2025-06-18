class DelayingJob < ApplicationJob
  include AcidicJob::Workflow

  def perform
    execute_workflow(unique_by: job_id) do |w|
      w.step :delay
      w.step :halt
      w.step :do_something
    end
  end

  def delay
    future_run = enqueue(wait: 14.days)
    ctx[:wait_until] = future_run.scheduled_at
  end

  def halt
    return if Time.now >= ctx[:wait_until]

    halt_workflow!
  end

  def do_something
    # idempotent because journal logging is idempotent via Set
    # but this means data logged must be identical across executions
    ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "scheduled_at"))
  end
end
