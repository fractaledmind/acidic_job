# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/for_each"

module Pro
  class ForEachTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :iterate_1, for_each: [1, 2]
          w.step :iterate_2, for_each: :zero_arity_enumerable
          w.step :iterate_3, for_each: :zero_arity_enumerator
          w.step :iterate_4, for_each: "cursor_keyreq_enumerable"
          w.step :iterate_5, for_each: "cursor_keyreq_enumerator"
        end
      end

      def iterate_1(item)
        # do thing with `item` idempotently
        # in this example, that requires checking the log before inserting
        ChaoticJob.log_to_journal!(item) if ChaoticJob.top_journal_entry != item
      end

      def iterate_2(item)
        # do thing with `item` idempotently
        # in this example, that requires checking the log before inserting
        ChaoticJob.log_to_journal!(item) if ChaoticJob.top_journal_entry != item
      end

      def iterate_3(item)
        # do thing with `item` idempotently
        # in this example, that requires checking the log before inserting
        ChaoticJob.log_to_journal!(item) if ChaoticJob.top_journal_entry != item
      end

      def iterate_4(item)
        # do thing with `item` idempotently
        # in this example, that requires checking the log before inserting
        ChaoticJob.log_to_journal!(item) if ChaoticJob.top_journal_entry != item
      end

      def iterate_5(item)
        # do thing with `item` idempotently
        # in this example, that requires checking the log before inserting
        ChaoticJob.log_to_journal!(item) if ChaoticJob.top_journal_entry != item
      end

      def zero_arity_enumerable
        [3, 4]
      end

      def zero_arity_enumerator
        [5, 6].each
      end

      def cursor_keyreq_enumerable(cursor:)
        [7, 8]
      end

      def cursor_keyreq_enumerator(cursor:)
        [9, 10].each
      end
    end

    def before_setup
      AcidicJob.plugins << AcidicJob::Plugins::Pro::ForEach
      super
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # Performed only the job
      assert_equal 1, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # performs primary IO operation once per iteration
      assert_equal 10, ChaoticJob.journal_size, ChaoticJob::Journal.entries
      assert_equal (1..10).to_a, ChaoticJob::Journal.entries

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # iterates over 3 item array before succeeding
      assert_equal 30, AcidicJob::Entry.count
      assert_equal(
        [
          %w[iterate_1 started],
          %w[iterate_1 for_each/iterated],
          %w[iterate_1 started],
          %w[iterate_1 for_each/iterated],
          %w[iterate_1 started],
          %w[iterate_1 succeeded],
          %w[iterate_2 started],
          %w[iterate_2 for_each/iterated],
          %w[iterate_2 started],
          %w[iterate_2 for_each/iterated],
          %w[iterate_2 started],
          %w[iterate_2 succeeded],
          %w[iterate_3 started],
          %w[iterate_3 for_each/iterated],
          %w[iterate_3 started],
          %w[iterate_3 for_each/iterated],
          %w[iterate_3 started],
          %w[iterate_3 succeeded],
          %w[iterate_4 started],
          %w[iterate_4 for_each/iterated],
          %w[iterate_4 started],
          %w[iterate_4 for_each/iterated],
          %w[iterate_4 started],
          %w[iterate_4 succeeded],
          %w[iterate_5 started],
          %w[iterate_5 for_each/iterated],
          %w[iterate_5 started],
          %w[iterate_5 for_each/iterated],
          %w[iterate_5 started],
          %w[iterate_5 succeeded],
],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only one context value for the cursor into the enumerable
      assert_equal 5, AcidicJob::Value.count
      assert_equal(
        [
          "for_each/iterate_1/cursor",
          "for_each/iterate_2/cursor",
          "for_each/iterate_3/cursor",
          "for_each/iterate_4/cursor",
          "for_each/iterate_5/cursor",
],
        AcidicJob::Value.pluck(:key)
      )
    end
  end
end
