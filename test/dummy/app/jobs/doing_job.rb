class DoingJob < ApplicationJob
  include AcidicJob::Workflow

  def perform
    execute_workflow(unique_by: job_id) do |w|
      w.step :do_something
    end
  end

  def do_something
    # idempotent because journal logging is idempotent via Set
    # but this means data logged must be identical across executions
    ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
  end
end