# frozen_string_literal: true

require "test_helper"

module Examples
  class NoOpTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :do_something
        end
      end

      def do_something
        # idempotent because journal logging is idempotent via Set
        # but this means data logged must be identical across executions
        ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # Performed only the job
      assert_equal 1, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # job is finished successfully
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # nothing happened beyond halting on the `delayed` step
      assert_equal 2, AcidicJob::Entry.count
      assert_equal(
        [
          %w[do_something started],
          %w[do_something succeeded],
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # the step method has executed
      assert_equal 1, ChaoticJob.journal_size
    end

    test_simulation(Job.new) do |_scenario|
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

      # only performs primary IO operations once per job
      assert_equal 1, ChaoticJob.journal_size, ChaoticJob.journal_entries
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
    end
  end
end
