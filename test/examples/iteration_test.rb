# frozen_string_literal: true

require "test_helper"

module Examples
  class IterationTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        @enumerable = (1..3).to_a
        execute_workflow(unique_by: job_id) do |w|
          w.step :step_1
        end
      end

      def step_1
        cursor = @ctx[:cursor] || 0
        item = @enumerable[cursor]
        return if item.nil?

        # do thing with `item` idempotently
        # in this case, that requires checking the log before inserting
        if ChaoticJob.top_journal_entry != item
          ChaoticJob.log_to_journal!(item)
        end

        @ctx[:cursor] = cursor + 1
        repeat_step!
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # Performed only the job
      assert_equal 1, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # performs primary IO operation once per iteration
      assert_equal 3, ChaoticJob.journal_size
      assert_equal [1, 2, 3], ChaoticJob::Journal.entries

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once()
      execution = AcidicJob::Execution.first

      # iterates over 3 item array before succeeding
      assert_equal 5, AcidicJob::Entry.count
      assert_equal(
        [%w[step_1 started],
         %w[step_1 started],
         %w[step_1 started],
         %w[step_1 started],
         %w[step_1 succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      # only one context value for the cursor into the enumerable
      assert_equal 1, AcidicJob::Value.count
      assert_equal 3, AcidicJob::Value.find_by(key: :cursor).value
    end

    test "scenario with error before updating cursor" do
      run_scenario(Job.new, glitch: ["before", "#{__FILE__}:28"]) do
        perform_all_jobs

        # Performed the job and its retry
        assert_equal 2, performed_jobs.size
        assert_equal 0, enqueued_jobs.size

        # performs primary IO operation once per iteration
        assert_equal 3, ChaoticJob.journal_size
        assert_equal [1, 2, 3], ChaoticJob::Journal.entries

        assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once()
        execution = AcidicJob::Execution.first

        # iterates over 3 item array before succeeding
        assert_equal 7, AcidicJob::Entry.count
        assert_equal(
          [%w[step_1 started],
           %w[step_1 errored],
           %w[step_1 started],
           %w[step_1 started],
           %w[step_1 started],
           %w[step_1 started],
           %w[step_1 succeeded]],
          execution.entries.order(timestamp: :asc).pluck(:step, :action)
        )

        # only one context value for the cursor into the enumerable
        assert_equal 1, AcidicJob::Value.count
        assert_equal 3, AcidicJob::Value.find_by(key: :cursor).value
      end
    end

    test "simulation" do
      run_simulation(Job.new) do |scenario|
        assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once()

        # performs primary IO operation once per iteration
        assert_equal 3, ChaoticJob.journal_size
        assert_equal [1, 2, 3], ChaoticJob::Journal.entries
      end
    end
  end
end
