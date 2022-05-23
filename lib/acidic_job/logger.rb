# frozen_string_literal: true

require "logger"
require "active_support/tagged_logging"

module AcidicJob
  class Logger < ::Logger
    def log_run_event(msg, job = nil, run = nil)
      tags = [
        run&.idempotency_key,
        inspect_name(job)
      ].compact

      tagged(*tags) { debug(msg) }
    end

    def inspect_name(obj)
      return if obj.nil?

      obj.inspect.split.first.remove("#<")
    end
  end

  def self.logger
    @logger ||= ActiveSupport::TaggedLogging.new(AcidicJob::Logger.new($stdout, level: :debug))
  end

  def self.logger=(new_logger)
    @logger = ActiveSupport::TaggedLogging.new(new_logger)
  end
end
