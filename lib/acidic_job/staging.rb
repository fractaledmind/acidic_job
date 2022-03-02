# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
	module Staging
		extend ActiveSupport::Concern

		def delete_staged_job_record
			return unless was_staged_job?

			staged_job_run.delete
			true
		rescue ActiveRecord::RecordNotFound
			true
		end

		def was_staged_job?
			identifier.start_with? "STG_"
		end

		def staged_job_run
			# "STG_#{idempotency_key}__#{encoded_global_id}"
			encoded_global_id = identifier.split("__").last
			staged_job_gid = "gid://" + Base64.decode64(encoded_global_id)

			GlobalID::Locator.locate(staged_job_gid)
		end
	end
end