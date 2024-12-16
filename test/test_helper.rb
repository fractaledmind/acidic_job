# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$VERBOSE = nil

require "bundler/setup"
require "rails/version"

p({ ruby: RUBY_VERSION, rails: Rails::VERSION::STRING })

require "combustion"
require "sqlite3"
Combustion.path = "test/combustion"
Combustion.initialize! :active_record, :active_job

require "rails/test_help"
require "chaotic_job"
require "acidic_job"

require "minitest/autorun"

ActiveSupport.on_load :active_job do
  self.queue_adapter = :test
end

# see: https://github.com/rails/rails/pull/48600
if ActiveRecord.respond_to?(:commit_transaction_on_non_local_return) &&
   Rails::VERSION::MAJOR >= 7 &&
   Rails::VERSION::MINOR <= 1
  ActiveRecord.commit_transaction_on_non_local_return = true
end

ActiveJob::Base.logger = ActiveRecord::Base.logger = Logger.new(ENV["LOG"].present? ? $stdout : IO::NULL)

class DefaultsError < StandardError; end
class DiscardableError < StandardError; end
class BreakingError < StandardError; end

class ActiveSupport::TestCase # rubocop:disable Style/ClassAndModuleChildren
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  include ChaoticJob::Helpers

  # Set default before_setup and after_teardown methods
  def before_setup
    ChaoticJob::Journal.reset!
    AcidicJob::Value.delete_all
    AcidicJob::Entry.delete_all
    AcidicJob::Execution.delete_all
    TestObject.delete_all
    performed_jobs.clear if defined?(performed_jobs)
    enqueued_jobs.clear if defined?(enqueued_jobs)
  end

  def after_teardown; end
end
