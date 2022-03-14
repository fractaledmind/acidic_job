# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module Extensions
    module ActionMailer
      extend ActiveSupport::Concern

      def deliver_acidicly(_options = {})
        job_class = ::ActionMailer::MailDeliveryJob

        job_args = [@mailer_class.name, @action.to_s, "deliver_now", @params, *@args]
        # for Sidekiq, this depends on the Sidekiq::Serialization extension
        serialized_job = job_class.new(job_args).serialize
        acidic_identifier = job_class.respond_to?(:acidic_identifier) ? job_class.acidic_identifier : :job_id
        key = IdempotencyKey.new(acidic_identifier).value_for(serialized_job)

        AcidicJob::Run.create!(
          staged: true,
          job_class: job_class.name,
          serialized_job: serialized_job,
          idempotency_key: key
        )
      end
      alias deliver_transactionally deliver_acidicly
    end
  end
end
