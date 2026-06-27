# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/undo"

UndoError = Class.new(StandardError) unless defined?(UndoError)

unless AcidicJob.plugins.include?(AcidicJob::Plugins::Pro::Undo)
  AcidicJob.plugins << AcidicJob::Plugins::Pro::Undo
end

module Pro
  class UndoTest < ActiveJob::TestCase
    # ============================================
    # Validation
    # ============================================

    test "validate accepts a symbol and normalizes to a string" do
      assert_equal "release", AcidicJob::Plugins::Pro::Undo.validate(:release)
    end

    test "validate rejects a non-method-name value" do
      error = assert_raises(ArgumentError) { AcidicJob::Plugins::Pro::Undo.validate(on: Thing) }
      assert_match(/must be a method name/, error.message)
    end

    test "fails fast when an undo method is undefined" do
      job_class = Class.new(ActiveJob::Base) do
        include AcidicJob::Workflow

        def perform
          execute_workflow(unique_by: job_id) do |w|
            w.step :do_it, undo: :nonexistent
          end
        end

        def do_it
          nil
        end
      end

      assert_raises(AcidicJob::UndefinedMethodError) { job_class.perform_now }
    end

    # ============================================
    # Rollback behavior
    # ============================================

    class SagaJob < ActiveJob::Base
      include AcidicJob::Workflow

      discard_on UndoError

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :reserve, undo: :release
          w.step :charge, undo: :refund
          w.step :ship
        end
      end

      def reserve
        ChaoticJob.push_to_journal!(:reserved)
      end

      def charge
        ChaoticJob.push_to_journal!(:charged)
      end

      def ship
        raise UndoError, "carrier down"
      end

      def release
        ChaoticJob.push_to_journal!(:released)
      end

      def refund
        ChaoticJob.push_to_journal!(:refunded)
      end
    end

    test "rolls back completed steps in reverse order on terminal failure" do
      SagaJob.perform_later
      perform_all_jobs # discard_on swallows the error after running rollback

      # forward: reserve, charge; ship fails -> reverse undo: refund, release
      assert_equal [ :reserved, :charged, :refunded, :released ], ChaoticJob::Journal.entries

      execution = AcidicJob::Execution.first
      assert_equal(
        %w[charge reserve],
        execution.entries.for_action("undo/undone").ordered.pluck(:step)
      )
    end

    class SuccessJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :reserve, undo: :release
          w.step :ship
        end
      end

      def reserve
        ChaoticJob.push_to_journal!(:reserved)
      end

      def ship
        ChaoticJob.push_to_journal!(:shipped)
      end

      def release
        ChaoticJob.push_to_journal!(:released)
      end
    end

    test "does not run any compensations when the workflow succeeds" do
      SuccessJob.perform_later
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      assert_equal [ :reserved, :shipped ], ChaoticJob::Journal.entries
      assert_not AcidicJob::Execution.first.entries.for_action("undo/undone").exists?
    end

    class PartialJob < ActiveJob::Base
      include AcidicJob::Workflow

      discard_on UndoError

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :first_step, undo: :undo_first
          w.step :boom
        end
      end

      def first_step
        ChaoticJob.push_to_journal!(:first)
      end

      def boom
        raise UndoError
      end

      def undo_first
        ChaoticJob.push_to_journal!(:undid_first)
      end
    end

    test "only compensates steps that actually completed" do
      PartialJob.perform_later
      perform_all_jobs

      # boom never succeeded (and has no undo), so only first_step is rolled back
      assert_equal [ :first, :undid_first ], ChaoticJob::Journal.entries
    end

    class FailingUndoJob < ActiveJob::Base
      include AcidicJob::Workflow

      discard_on UndoError

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :first_step, undo: :undo_first   # this compensation will raise
          w.step :second_step, undo: :undo_second
          w.step :boom
        end
      end

      def first_step
        ChaoticJob.push_to_journal!(:first)
      end

      def second_step
        ChaoticJob.push_to_journal!(:second)
      end

      def boom
        raise UndoError
      end

      def undo_first
        raise UndoError, "rollback failed"
      end

      def undo_second
        ChaoticJob.push_to_journal!(:undid_second)
      end
    end

    test "a failing compensation does not block the others and is recorded" do
      FailingUndoJob.perform_later
      perform_all_jobs

      # reverse: second's undo succeeds; first's undo raises but doesn't stop it
      assert_equal [ :first, :second, :undid_second ], ChaoticJob::Journal.entries

      execution = AcidicJob::Execution.first
      assert_equal [ "second_step" ], execution.entries.for_action("undo/undone").ordered.pluck(:step)
      assert_equal [ "first_step" ], execution.entries.for_action("undo/failed").ordered.pluck(:step)
    end
  end
end
