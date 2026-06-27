# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/compensate"

CompensateError = Class.new(StandardError) unless defined?(CompensateError)
CompensateOtherError = Class.new(StandardError) unless defined?(CompensateOtherError)

# Register at load time (not in `before_setup`) so the plugin is active during
# `test_simulation`'s callstack capture, which runs when the class is defined.
unless AcidicJob.plugins.include?(AcidicJob::Plugins::Pro::Compensate)
  AcidicJob.plugins << AcidicJob::Plugins::Pro::Compensate
end

module Pro
  class CompensateTest < ActiveJob::TestCase

    # ============================================
    # Happy path
    # ============================================

    class TransientJob < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on CompensateError, attempts: 5, wait: 0

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :risky, compensate: { on: CompensateError, with: :cleanup }
          w.step :finish
        end
      end

      def risky
        raise CompensateError if executions < 3

        ChaoticJob.push_to_journal!(:risky_ok)
      end

      def cleanup
        ChaoticJob.push_to_journal!(:cleaned)
      end

      def finish
        ChaoticJob.push_to_journal!(:finished)
      end
    end

    test "compensates on each matching failure, re-raises, and eventually succeeds on retry" do
      TransientJob.perform_later
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # risky failed on executions 1 and 2 (compensating + errored each), then
      # succeeded on execution 3
      assert_equal(
        [
          %w[risky started],
          %w[risky compensate/compensating],
          %w[risky errored],
          %w[risky started],
          %w[risky compensate/compensating],
          %w[risky errored],
          %w[risky started],
          %w[risky succeeded],
          %w[finish started],
          %w[finish succeeded]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # cleanup ran once per failure, then the real work + finish ran once each
      assert_equal [ :cleaned, :cleaned, :risky_ok, :finished ], ChaoticJob::Journal.entries
    end

    # ============================================
    # Failure scenarios
    # ============================================

    class NonMatchingJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :risky, compensate: { on: CompensateError, with: :cleanup }
        end
      end

      def risky
        raise CompensateOtherError, "unexpected"
      end

      def cleanup
        ChaoticJob.push_to_journal!(:cleaned)
      end
    end

    test "does NOT compensate for a non-matching error and lets it propagate" do
      assert_raises(CompensateOtherError) { NonMatchingJob.perform_now }

      execution = AcidicJob::Execution.first
      # the bug this guards against: a non-matching error must not be swallowed
      # and the step must not be recorded as succeeded
      refute execution.entries.for_action("compensate/compensating").exists?
      assert execution.entries.for_step("risky").for_action("errored").exists?
      refute execution.entries.for_step("risky").for_action("succeeded").exists?
      assert_equal 0, ChaoticJob.journal_size
    end

    class PermanentJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :always_fails, compensate: { on: CompensateError, with: :cleanup }
        end
      end

      def always_fails
        raise CompensateError, "permanent"
      end

      def cleanup
        ChaoticJob.push_to_journal!(:cleaned)
      end
    end

    test "compensates and then re-raises on a permanent matching failure" do
      assert_raises(CompensateError) { PermanentJob.perform_now }

      execution = AcidicJob::Execution.first
      assert execution.entries.for_action("compensate/compensating").exists?
      assert execution.entries.for_step("always_fails").for_action("errored").exists?
      refute execution.entries.for_step("always_fails").for_action("succeeded").exists?
      assert_equal [ :cleaned ], ChaoticJob::Journal.entries
    end

    class FailingCleanupJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :risky, compensate: { on: CompensateError, with: :bad_cleanup }
        end
      end

      def risky
        raise CompensateError
      end

      def bad_cleanup
        raise CompensateOtherError, "cleanup blew up"
      end
    end

    test "propagates an error raised by the compensation method itself" do
      assert_raises(CompensateOtherError) { FailingCleanupJob.perform_now }

      execution = AcidicJob::Execution.first
      # compensating is recorded before the cleanup runs
      assert execution.entries.for_action("compensate/compensating").exists?
      assert execution.entries.for_step("risky").for_action("errored").exists?
      refute execution.entries.for_step("risky").for_action("succeeded").exists?
    end

    # ============================================
    # Chaos: injected failures at every seam
    # ============================================

    class SimJob < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on CompensateError, attempts: 10, wait: 0

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :risky, compensate: { on: CompensateError, with: :cleanup }
          w.step :finish
        end
      end

      def risky
        raise CompensateError if executions < 2

        ChaoticJob.log_to_journal!(:risky_ok) # Set-backed: idempotent
      end

      def cleanup
        # idempotent cleanup
      end

      def finish
        ChaoticJob.log_to_journal!(:finished)
      end
    end

    test_simulation(SimJob.new) do |_scenario|
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

      # no matter where a failure is injected, the workflow finishes with the
      # real work and the follow-up step each having run
      assert_includes ChaoticJob::Journal.entries, :risky_ok
      assert_includes ChaoticJob::Journal.entries, :finished
    end
  end
end
