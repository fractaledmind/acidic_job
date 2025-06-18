class WaitingJob < ApplicationJob
  include AcidicJob::Workflow

  def perform
    execute_workflow(unique_by: job_id) do |w|
      w.step :check
      w.step :do_something
    end
  end

  def check
    # this is the condition that will be checked every time the step is retried
    # to determine whether to continue to the next step or not
    return if conditional?

    enqueue(wait: 2.days)

    halt_workflow!
  end

  def do_something
    # idempotent because journal logging is idempotent via Set
    # but this means data logged must be identical across executions
    ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "scheduled_at"))
  end

  def conditional?
    ChaoticJob.switch_on? || executions == 10
  end
end