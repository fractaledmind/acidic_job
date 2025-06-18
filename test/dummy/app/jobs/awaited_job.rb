class AwaitedJob < ApplicationJob
  attr_accessor :execution

  after_perform do |job|
    job.execution.context[job.job_id] = true
    job.execution.enqueue_job
  end

  def perform(execution)
    self.execution = execution
    ChaoticJob.log_to_journal!(serialize)
  end
end