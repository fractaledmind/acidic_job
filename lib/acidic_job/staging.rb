# frozen_string_literal: true

require "active_support/concern"
require "global_id/locator"

module AcidicJob
  module Staging
    extend ActiveSupport::Concern

    private

    def was_staged_job?
      identifier.start_with? "STG__"
    end

    def staged_job_run
      # "STG_#{idempotency_key}__#{encoded_global_id}"
      encoded_global_id = identifier.split("__").last
      staged_job_gid = "gid://#{Base64.decode64(encoded_global_id)}"

      GlobalID::Locator.locate(staged_job_gid)
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def identifier
      return jid if defined?(jid) && !jid.nil?
      return job_id if defined?(job_id) && !job_id.nil?

      # might be defined already in `with_acidity` method
      acidic_identifier = self.class.acidic_identifier
      @__acidic_job_idempotency_key ||= IdempotencyKey.new(acidic_identifier)
                                                      .value_for(self, *@__acidic_job_args, **@__acidic_job_kwargs)

      @__acidic_job_idempotency_key
    end
  end
end
