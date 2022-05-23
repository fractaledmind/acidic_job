# frozen_string_literal: true

require "logger"

module AcidicJob
  class Logger < ::Logger; end

  def self.logger
    @logger ||= AcidicJob::Logger.new($stdout, level: :info)
  end

  def self.logger=(new_logger)
    @logger = new_logger
  end
end
