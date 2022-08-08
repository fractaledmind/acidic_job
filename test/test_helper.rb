# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"
require "rails/version"

p({ ruby: RUBY_VERSION, rails: Rails::VERSION::STRING })

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

require "acidic_job"
require "minitest/autorun"

GlobalID.app = :test

class CustomErrorForTesting < StandardError; end
class RareErrorForTesting < StandardError; end
  
module Cases; end
module Cases::ActiveJob; end
module Cases::ActiveKiq; end

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

require "combustion"
require "sqlite3"
Combustion.path = "test/combustion"
Combustion.initialize! :active_record

if ENV["LOG"].present?
  ActiveJob::Base.logger = ActiveRecord::Base.logger = Logger.new($stdout)
else
  ActiveJob::Base.logger = ActiveRecord::Base.logger = Logger.new(IO::NULL)
  AcidicJob.silence_logger!
end
