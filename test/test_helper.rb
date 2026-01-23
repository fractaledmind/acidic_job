# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

# Coverage mode: COVERAGE=1 bin/rails test
# - SimpleCov is started in bin/rails before loading Rails or the gem
# - Tests run serially for accurate coverage tracking
#
# Normal mode: bin/rails test
# - No coverage overhead
# - Tests run in parallel for speed

require_relative "../test/dummy/config/environment"

puts ""
puts "Running Ruby #{RUBY_VERSION} with Rails #{Rails::VERSION::STRING} on #{ActiveRecord::Base.connection.adapter_name}"

ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
ActiveRecord::Migrator.migrations_paths << File.expand_path("../db/migrate", __dir__)
require "rails/test_help"
require "minitest/mock"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end

ActiveSupport.on_load :active_job do
  self.queue_adapter = :test
end

# see: https://github.com/rails/rails/pull/48600
if ActiveRecord.respond_to?(:commit_transaction_on_non_local_return) &&
    Rails::VERSION::MAJOR >= 7 &&
    Rails::VERSION::MINOR <= 1

  ActiveRecord.commit_transaction_on_non_local_return = true
end

if ActiveSupport.respond_to?(:to_time_preserves_timezone)
  if Rails::VERSION::MAJOR >= 8
    ActiveSupport.to_time_preserves_timezone = :zone
  else
    ActiveSupport.to_time_preserves_timezone = true
  end
end

ActiveJob::Base.logger = ActiveRecord::Base.logger = AcidicJob.logger = Logger.new(ENV["LOG"].present? ? $stdout : IO::NULL)

require "chaotic_job"

class DefaultsError < StandardError; end
class DiscardableError < StandardError; end
class BreakingError < StandardError; end

class ActiveSupport::TestCase
  # Run tests in parallel for speed, but disable parallelization entirely
  # when collecting coverage to ensure accurate results
  unless ENV["COVERAGE"]
    parallelize(workers: :number_of_processors)
  end

  include ChaoticJob::Helpers

  # Set default before_setup and after_teardown methods
  def before_setup
    ChaoticJob::Journal.reset!
    AcidicJob::Value.delete_all
    AcidicJob::Entry.delete_all
    AcidicJob::Execution.delete_all
    Thing.delete_all
    performed_jobs.clear if defined?(performed_jobs)
    enqueued_jobs.clear if defined?(enqueued_jobs)
  end

  def after_teardown; end

  def assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once(context_on_error = nil)
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
end
