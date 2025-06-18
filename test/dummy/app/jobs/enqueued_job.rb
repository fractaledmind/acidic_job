class EnqueuedJob < ApplicationJob
  attr_accessor :execution

  after_perform do |job|
    job.execution.context[job.job_id] = true
  end

  def perform(execution)
    self.execution = execution
    # idempotent because journal logging is idempotent via Set
    # but this means data logged must be identical across executions
    ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
  end
end