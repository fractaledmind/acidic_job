# frozen_string_literal: true

require "active_job/configured_job"

module AcidicJob
  class ConfiguredJob < ::ActiveJob::ConfiguredJob
    def perform_acidicly(...)
      @job_class.new(...).set(@options).perform_acidicly
    end
  end
end
