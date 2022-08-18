# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"
require "rails/version"

p({ ruby: RUBY_VERSION, rails: Rails::VERSION::STRING })

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  enable_coverage :branch
  primary_coverage :branch
end

require "acidic_job"
require "minitest/autorun"

# Filter out Minitest backtrace while allowing backtrace from other libraries
# to be shown.
Minitest.backtrace_filter = Minitest::BacktraceFilter.new

GlobalID.app = :test

class CustomErrorForTesting < StandardError; end
class RareErrorForTesting < StandardError; end

class Performance
  def self.reset!
    @performances = 0
  end

  def self.performed!
    @performances += 1
  end

  class << self
    attr_reader :performances
  end
end

class MyCustomObject
  def initialize(state)
    @state = state
  end

  def serializable_hash
    { state: @state }
  end
end

class MyCustomSerializer < ActiveJob::Serializers::ObjectSerializer
  def serialize?(argument)
    argument.is_a?(MyCustomObject)
  end

  def serialize(custom_object)
    super(custom_object.serializable_hash)
  end

  def deserialize(hash)
    MyCustomObject.new(hash)
  end
end

require "combustion"
require "sqlite3"
Combustion.path = "test/combustion"
Combustion.initialize! :active_record, :active_job do
  require "noticed"
  config.active_job.custom_serializers << MyCustomSerializer
end

if ENV["LOG"].present?
  ActiveJob::Base.logger = ActiveRecord::Base.logger = Logger.new($stdout)
else
  ActiveJob::Base.logger = ActiveRecord::Base.logger = Logger.new(IO::NULL)
  AcidicJob.silence_logger!
end
