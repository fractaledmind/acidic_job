class DeliveringJob < ApplicationJob
  include AcidicJob::Workflow

  def perform
    execute_workflow(unique_by: job_id) do |w|
      w.step :deliver_email
      w.step :deliver_parameterized_email
      w.step :do_something
    end
  end

  def deliver_email
    # enqueue the message for delivery once, and store it.
    # on retries, just fetch it from the context
    ctx.fetch(:email_1) { TestMailer.hello_world.deliver_later }
  end

  def deliver_parameterized_email
    # enqueue the message for delivery once, and store it.
    # on retries, just fetch it from the context
    ctx.fetch(:email_2) { TestMailer.with({ recipient: "me@mail.com" }).hello_world.deliver_later }
  end

  def do_something
    # idempotent because journal logging is idempotent via Set
    # but this means data logged must be identical across executions
    ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
  end
end