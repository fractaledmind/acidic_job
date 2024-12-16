# frozen_string_literal: true

require "test_helper"

class TestJob < ActiveJob::Base
  def perform
    ChaoticJob.log_to_journal!(serialize)
  end
end

module Examples
  class EnqueuingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :enqueue_job
          w.step :do_something
        end
      end

      def enqueue_job
        TestJob.perform_later
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize)
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # Performed the job and the enqueued job
      assert_equal 2, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 2, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == TestJob.name }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # simple walkthrough of the execution
      assert_equal 4, AcidicJob::Entry.count
      assert_equal(
        [%w[enqueue_job started],
         %w[enqueue_job succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      # no context needed or stored
      assert_equal 0, AcidicJob::Value.count
    end

    test "simulation" do
      run_simulation(Job.new) do |_scenario|
        assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once

        # only performs primary IO operations once per job
        assert_equal 2, ChaoticJob.journal_size
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == TestJob.name }.size
      end
    end
  end
end
