# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/retry"

RetryFlakyError = Class.new(StandardError) unless defined?(RetryFlakyError)
RetryOtherError = Class.new(StandardError) unless defined?(RetryOtherError)

# Register at load time (not in `before_setup`) so the plugin is active during
# `test_simulation`'s callstack capture, which runs when the class is defined.
unless AcidicJob.plugins.include?(AcidicJob::Plugins::Pro::Retry)
  AcidicJob.plugins << AcidicJob::Plugins::Pro::Retry
end

module Pro
  class RetryTest < ActiveJob::TestCase
    # ============================================
    # Validation
    # ============================================

    test "validate accepts attempts only" do
      assert_equal({ "attempts" => 3, "backoff" => "exponential" }, AcidicJob::Plugins::Pro::Retry.validate(attempts: 3))
    end

    test "validate accepts on + attempts + backoff" do
      assert_equal(
        { "attempts" => 5, "on" => [ RetryFlakyError ], "backoff" => "linear" },
        AcidicJob::Plugins::Pro::Retry.validate(on: RetryFlakyError, attempts: 5, backoff: :linear)
      )
    end

    test "validate accepts a fixed numeric backoff" do
      assert_equal({ "attempts" => 2, "backoff" => 2 }, AcidicJob::Plugins::Pro::Retry.validate(attempts: 2, backoff: 2))
    end

    test "validate rejects a non-hash" do
      assert_raises(AcidicJob::Plugins::Pro::Retry::InvalidOptionsError) { AcidicJob::Plugins::Pro::Retry.validate(:nope) }
    end

    test "validate rejects a missing attempts" do
      assert_raises(AcidicJob::Plugins::Pro::Retry::InvalidOptionsError) { AcidicJob::Plugins::Pro::Retry.validate(on: RetryFlakyError) }
    end

    test "validate rejects a bad backoff" do
      assert_raises(ArgumentError) { AcidicJob::Plugins::Pro::Retry.validate(attempts: 3, backoff: :nope) }
    end

    # ============================================
    # Behavior
    # ============================================

    class TransientJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :flaky, retry: { on: RetryFlakyError, attempts: 3, backoff: 1 }
          w.step :finish
        end
      end

      def flaky
        # fails on the first two executions, succeeds on the third
        raise RetryFlakyError if executions < 3

        ChaoticJob.log_to_journal!(:flaky_ok)
      end

      def finish
        ChaoticJob.log_to_journal!(:finished)
      end
    end

    test "retries a matching error with backoff and eventually succeeds" do
      TransientJob.perform_later
      # the reschedules are future-dated, but the performer drains them regardless
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      assert_equal(
        [
          %w[flaky started],
          %w[flaky retry/retrying],
          %w[flaky halted],
          %w[flaky started],
          %w[flaky retry/retrying],
          %w[flaky halted],
          %w[flaky started],
          %w[flaky succeeded],
          %w[finish started],
          %w[finish succeeded]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      assert_equal 2, execution.entries.for_action("retry/retrying").count
      assert_equal [ :flaky_ok, :finished ], ChaoticJob::Journal.entries
    end

    class NonMatchingJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :boom, retry: { on: RetryFlakyError, attempts: 3 }
        end
      end

      def boom
        raise RetryOtherError, "not retryable"
      end
    end

    test "does not retry a non-matching error" do
      assert_raises(RetryOtherError) { NonMatchingJob.perform_now }

      execution = AcidicJob::Execution.first
      assert_not execution.entries.for_action("retry/retrying").exists?
      assert execution.entries.for_step("boom").for_action("errored").exists?
    end

    class ExhaustingJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :always_fails, retry: { on: RetryFlakyError, attempts: 3, backoff: 1 }
        end
      end

      def always_fails
        raise RetryFlakyError, "permanent"
      end
    end

    test "propagates the error once the retry budget is exhausted" do
      ExhaustingJob.perform_later
      assert_raises(RetryFlakyError) { perform_all_jobs }

      execution = AcidicJob::Execution.first
      # attempts: 3 -> 2 reschedules, then the third failure propagates
      assert_equal 2, execution.entries.for_action("retry/retrying").count
      assert execution.entries.for_step("always_fails").for_action("errored").exists?
      assert_not execution.entries.for_step("always_fails").for_action("succeeded").exists?
    end

    class BackoffJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :flaky, retry: { on: RetryFlakyError, attempts: 4, backoff: :exponential }
        end
      end

      def flaky
        raise RetryFlakyError if executions < 4

        ChaoticJob.log_to_journal!(:ok)
      end
    end

    test "records exponential backoff waits per attempt" do
      BackoffJob.perform_later
      perform_all_jobs

      execution = AcidicJob::Execution.first
      waits = execution.entries.for_action("retry/retrying").ordered.map { |e| e.data[:wait] }
      assert_equal [ 1, 2, 4 ], waits
    end

    # ============================================
    # Chaos
    # ============================================

    class SimJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :flaky, retry: { on: RetryFlakyError, attempts: 5, backoff: 1 }
          w.step :finish
        end
      end

      def flaky
        raise RetryFlakyError if executions < 2

        ChaoticJob.log_to_journal!(:flaky_ok)
      end

      def finish
        ChaoticJob.log_to_journal!(:finished)
      end
    end

    test_simulation(SimJob.new) do |_scenario|
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      assert_includes ChaoticJob::Journal.entries, :flaky_ok
      assert_includes ChaoticJob::Journal.entries, :finished
    end
  end
end
