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
Combustion.initialize! :active_record, :active_job, :action_mailer

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

ActiveSupport.to_time_preserves_timezone = true if ActiveSupport.respond_to?(:to_time_preserves_timezone)

# rubocop:disable Layout/LineLength
ActiveJob::Base.logger = ActiveRecord::Base.logger = AcidicJob.logger = Logger.new(ENV["LOG"].present? ? $stdout : IO::NULL)
# rubocop:enable Layout/LineLength

class DefaultsError < StandardError; end
class DiscardableError < StandardError; end
class BreakingError < StandardError; end

def assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once(context_on_error = nil)
  # only one executions
  assert_equal 1, AcidicJob::Execution.count, context_on_error
  execution = AcidicJob::Execution.first

  # that is finished
  assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to, context_on_error

  # each step only succeeds once
  logs = AcidicJob::Entry.where(execution: execution).order(timestamp: :asc).pluck(:step, :action)
  step_logs = logs.each_with_object({}) { |(step, status), hash| (hash[step] ||= []) << status }

  step_logs.each_value do |actions|
    assert_equal 1, actions.count { |it| it == "succeeded" }, actions
  end
end

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

class ActiveJob::TestCase # rubocop:disable Style/ClassAndModuleChildren
  # This needs to be set to `nil` to avoid an odd bug in Rails <= 7.1
  # where the queue adapter is given a fresh instance of the test adapter
  # after the `after_teardown` hook is called.
  def queue_adapter_for_test
    nil
  end
end
