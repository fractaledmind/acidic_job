# frozen_string_literal: true

require "active_support/concern"



module AcidicJob
	module Extensions
		module ActionMailer
			extend ActiveSupport::Concern

			def deliver_acidicly(_options = {})
				job = delivery_job_class
				job_args = if job <= ActionMailer::Parameterized::MailDeliveryJob
										 [@mailer_class.name, @action.to_s, "deliver_now", { params: @params, args: @args }]
									 else
										 [@mailer_class.name, @action.to_s, "deliver_now", @params, *@args]
									 end
				# for Sidekiq, this depends on the Sidekiq::Serialization extension
				serialized_job = job.new(job_args).serialize
				
				AcidicJob::Run.create!(
					staged: true,
					job_class: job.name,
					serialized_job: serialized_job,
					idempotency_key: IdempotencyKey.value_for(serialized_job)
				)
			end
			alias_method :deliver_transactionally, :deliver_acidicly
		end
	end
end
