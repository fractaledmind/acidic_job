# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/await_signal"

unless AcidicJob.plugins.include?(AcidicJob::Plugins::Pro::AwaitSignal)
  AcidicJob.plugins << AcidicJob::Plugins::Pro::AwaitSignal
end

module Pro
  class AwaitSignalTest < ActiveJob::TestCase
    def before_setup
      ChaoticJob.switch_off!
      super
    end

    # ============================================
    # Validation
    # ============================================

    test "validate accepts a symbol and normalizes to a string" do
      assert_equal "approved?", AcidicJob::Plugins::Pro::AwaitSignal.validate(:approved?)
    end

    test "validate rejects a non-method-name value" do
      error = assert_raises(ArgumentError) { AcidicJob::Plugins::Pro::AwaitSignal.validate(every: 1) }
      assert_match(/must be a method name/, error.message)
    end

    test "fails fast when the signal method is undefined" do
      job_class = Class.new(ActiveJob::Base) do
        include AcidicJob::Workflow

        def perform
          execute_workflow(unique_by: job_id) do |w|
            w.step :gate, await_signal: :nonexistent
          end
        end

        def gate
          nil
        end
      end

      assert_raises(AcidicJob::UndefinedMethodError) { job_class.perform_now }
    end

    # ============================================
    # Behavior
    # ============================================

    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform(id)
        execute_workflow(unique_by: id) do |w|
          w.step :await_approval, await_signal: :approved?
          w.step :activate
        end
      end

      def approved?
        ChaoticJob.switch_on?
      end

      def await_approval
        ChaoticJob.log_to_journal!(:approval_seen)
      end

      def activate
        ChaoticJob.log_to_journal!(:activated)
      end
    end

    test "proceeds immediately when the signal is already present" do
      ChaoticJob.switch_on!

      Job.perform_later("order-1")
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      assert_equal [ :approval_seen, :activated ], ChaoticJob::Journal.entries
    end

    test "halts (without rescheduling) until the signal arrives, then resumes on re-trigger" do
      Job.perform_later("order-1")
      perform_all_jobs

      # signal absent: halted on the gate, body not run, and NOTHING re-enqueued
      execution = AcidicJob::Execution.first
      assert_equal "await_approval", execution.recover_to
      assert_equal 0, ChaoticJob.journal_size
      assert_equal 0, enqueued_jobs.size
      assert_equal(
        [ %w[await_approval started], %w[await_approval await_signal/awaiting], %w[await_approval halted] ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # external event arrives: flip the signal and re-trigger the same unique_by
      ChaoticJob.switch_on!
      Job.perform_later("order-1")
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      assert_equal [ :approval_seen, :activated ], ChaoticJob::Journal.entries
    end

    test "re-halts when re-triggered while the signal is still absent" do
      Job.perform_later("order-1")
      perform_all_jobs

      # a premature re-trigger (signal still off) just halts again
      Job.perform_later("order-1")
      perform_all_jobs

      execution = AcidicJob::Execution.first
      assert_equal "await_approval", execution.recover_to
      assert_equal 2, execution.entries.for_action("await_signal/awaiting").count
      assert_equal 0, ChaoticJob.journal_size
    end
  end
end
