# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module Extensions
    module ActionMailer
      extend ActiveSupport::Concern

      def deliver_acidicly(_options = {})
        job = ::ActionMailer::MailDeliveryJob

        job_args = [@mailer_class.name, @action.to_s, "deliver_now", @params, *@args]
        # for Sidekiq, this depends on the Sidekiq::Serialization extension
        serialized_job = job.new(job_args).serialize

        AcidicJob::Run.create!(
          staged: true,
          job_class: job.name,
          serialized_job: serialized_job,
          idempotency_key: IdempotencyKey.value_for(serialized_job)
        )
      end
      alias deliver_transactionally deliver_acidicly
    end
  end
end
