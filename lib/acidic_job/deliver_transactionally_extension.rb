# frozen_string_literal: true

module AcidicJob
  module DeliverTransactionallyExtension
    def deliver_transactionally(options = {})
      job = delivery_job_class

      attributes = {
        adapter: "activejob",
        job_name: job.name
      }

      job_args = if job <= ActionMailer::Parameterized::MailDeliveryJob
        [@mailer_class.name, @action.to_s, "deliver_now", {params: @params, args: @args}]
      else
        [@mailer_class.name, @action.to_s, "deliver_now", @params, *@args]
      end

      attributes[:job_args] = job.new(job_args).serialize

      AcidicJob::Staged.create!(attributes)
    end
  end
end
