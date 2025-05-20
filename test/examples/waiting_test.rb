# frozen_string_literal: true

require "test_helper"

module Examples
  class WaitingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :wait_until
          w.step :do_something
        end
      end

      def wait_until
        # this is the condition that will be checked every time the step is retried
        # to determine whether to continue to the next step or not
        return if step_retrying?

        enqueue(wait: 2.seconds)

        halt_workflow!
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize)
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # Performed the original job and waited job
      assert_equal 2, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once
      assert_equal 1, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # halts once as condition is false, then continues after 2 seconds
      assert_equal 6, AcidicJob::Entry.count
      assert_equal(
        [
          %w[wait_until started],
          %w[wait_until halted],
          %w[wait_until started],
          %w[wait_until succeeded],
          %w[do_something started],
          %w[do_something succeeded],
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # no context needed or stored
      assert_equal 0, AcidicJob::Value.count
    end

    test "simulation" do
      run_simulation(Job.new) do |_scenario|
        assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once

        # only performs primary IO operations once
        assert_equal 1, ChaoticJob.journal_size
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      end
    end
  end
end
