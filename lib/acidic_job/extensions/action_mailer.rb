# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module Extensions
    module ActionMailer
      extend ActiveSupport::Concern

      def deliver_acidicly(_options = {})
        job_class = ::ActionMailer::Base.delivery_job
        job_args = [@mailer_class.name, @action.to_s, "deliver_now", @params, *@args]
        job = job_class.new(job_args)

        AcidicJob::Run.stage!(job)
      end
    end
  end
end
