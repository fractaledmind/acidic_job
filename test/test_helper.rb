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

class Performance
  def self.reset!
    @performances = 0
  end

  def self.performed!
    @performances += 1
  end

  def self.processed!(item, scope: :default)
    @processed_items ||= {}
    @processed_items[scope] ||= []
    @processed_items[scope] << item
  end

  def self.processed_items(scope = :default)
    @processed_items[scope]
  end

  class << self
    attr_reader :performances
  end
end

class DefaultsError < StandardError; end
class DiscardableError < StandardError; end
class BreakingError < StandardError; end
