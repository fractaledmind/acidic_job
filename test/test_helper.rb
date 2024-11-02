# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$VERBOSE = nil

require "bundler/setup"

require "combustion"
require "sqlite3"
Combustion.path = "test/combustion"
Combustion.initialize! :active_record, :active_job

require "rails/test_help"
require "acidic_job"

require "minitest/autorun"

ActiveSupport.on_load :active_job do
  self.queue_adapter = :test
end

ActiveJob::Base.logger = ActiveRecord::Base.logger = Logger.new(ENV["LOG"].present? ? $stdout : IO::NULL)

module Performance
  extend self

  def reset!
    @performances = {}
  end

  def performed!(item = 1, scope: :default)
    @performances ||= {}
    @performances[scope] ||= []
    @performances[scope] << item
  end

  def total(scope: :default)
    @performances[scope]&.size || 0
  end

  def all(scope: :default)
    @performances[scope]
  end
end

class DefaultsError < StandardError; end
class DiscardableError < StandardError; end
class BreakingError < StandardError; end
