# frozen_string_literal: true

require "test_helper"

module Examples
  class DelayingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :delay
          w.step :halt, transactional: true
          w.step :do_something
        end
      end

      def delay
        enqueue(wait: 14.days)
        @ctx[:halt] = true
      end

      def halt
        return unless @ctx[:halt]

        @ctx[:halt] = false
        halt_step!
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize)
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs_within(1.minute)

      # Performed the original job
      assert_equal 1, performed_jobs.select { |job| job["job_class"] == Job.name }.size
      # Job in 14 days hasn't been executed yet
      assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == Job.name }.size
      assert_equal 1, performed_jobs.size
      assert_equal 1, enqueued_jobs.size

      # First, test the state of the execution after the first job is halted
      assert_equal 0, ChaoticJob.journal_size
      assert_equal 1, AcidicJob::Execution.count
      execution = AcidicJob::Execution.first

      # execution is for this job and is paused on the `halt` step
      assert_equal Job.name, execution.serialized_job["job_class"]
      assert_equal "halt", execution.recover_to

      # nothing happened beyond halting on the `halt` step
      assert_equal 4, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt halted]],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only one context value for the signal to halt, which is already false
      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      # Now, perform the future scheduled job and check the final state of the execution
      perform_all_jobs_after(14.days)

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # after the halting step, when the future version of the job is performed it completes successfully
      assert_equal 8, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt halted],
         %w[halt started],
         %w[halt succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only one context value for the signal to halt that is still false
      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      # the most recent job that was performed is the future scheduled job
      assert_equal 1, ChaoticJob.journal_size
      job_that_performed = ChaoticJob.top_journal_entry

      assert_in_delta Time.parse(job_that_performed["scheduled_at"]).to_i, 14.days.from_now.to_i, 1, 1
    end

    test "scenario with error before halt_step!" do
      run_scenario(Job.new, glitch: ["before", "#{__FILE__}:27"]) do
        perform_all_jobs_within(1.minute)
      end

      # Performed the first job, then retried it
      assert_equal 2, performed_jobs.size
      # Job in 14 days hasn't been executed yet
      assert_equal 1, enqueued_jobs.size

      # First, test the state of the execution after the first job is halted
      assert_equal 0, ChaoticJob.journal_size
      assert_equal 1, AcidicJob::Execution.count
      execution = AcidicJob::Execution.first

      # execution is for this job and is paused on the `halt` step
      assert_equal Job.name, execution.serialized_job["job_class"]
      assert_equal "halt", execution.recover_to

      # nothing happened beyond erroring then halting on the `halt` step
      assert_equal 6, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt errored],
         %w[halt started],
         %w[halt halted]],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only one context value for the signal to halt, which is already false
      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      # Now, perform the future scheduled job and check the final state of the execution
      perform_all_jobs_after(14.days)

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # after the halting step, when the future version of the job is performed it completes successfully
      assert_equal 10, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt errored],
         %w[halt started],
         %w[halt halted],
         %w[halt started],
         %w[halt succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only one context value for the signal to halt that is still false
      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      # the most recent job that was performed is the future scheduled job
      assert_equal 1, ChaoticJob.journal_size
      job_that_performed = ChaoticJob.top_journal_entry

      assert_in_delta Time.parse(job_that_performed["scheduled_at"]).to_i, 14.days.from_now.to_i, 1
    end

    test "scenario with error before setting halt intention" do
      run_scenario(Job.new, glitch: ["before", "#{__FILE__}:20"]) do
        perform_all_jobs_within(1.minute)
      end

      # Performed the first job, then retried it
      assert_equal 2, performed_jobs.size
      # Job in 14 days hasn't been executed yet, but has been enqueued twice
      assert_equal 2, enqueued_jobs.size

      # First, test the state of the execution after the first job is halted
      assert_equal 0, ChaoticJob.journal_size
      assert_equal 1, AcidicJob::Execution.count
      execution = AcidicJob::Execution.first

      # execution is for this job and is paused on the `halt` step
      assert_equal Job.name, execution.serialized_job["job_class"]
      assert_equal "halt", execution.recover_to

      # nothing happened beyond erroring then halting on the `halt` step
      assert_equal 6, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay errored],
         %w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt halted]],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only one context value for the signal to halt, which is already false
      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      # Now, perform the future scheduled job and check the final state of the execution
      perform_all_jobs_after(14.days)

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # after the halting step, when the future version of the job is performed it completes successfully
      assert_equal 10, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay errored],
         %w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt halted],
         %w[halt started],
         %w[halt succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only one context value for the signal to halt that is still false
      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      # the most recent job that was performed is the future scheduled job
      assert_equal 1, ChaoticJob.journal_size
      job_that_performed = ChaoticJob.top_journal_entry

      assert_in_delta Time.parse(job_that_performed["scheduled_at"]).to_i, 14.days.from_now.to_i, 1
    end

    test "simulation" do
      run_simulation(Job.new) do |_scenario|
        assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once

        # typically only job, error, and future are performed, but when error occurs inside `delay` step,
        # two futures are performed; this is safe though because the job is an idempotent workflow
        assert_includes 3..4, performed_jobs.size

        # only performs primary IO operations once and at the correct time
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
        job_that_performed = ChaoticJob.top_journal_entry

        assert_in_delta Time.parse(job_that_performed["scheduled_at"]).to_i, 14.days.from_now.to_i, 1, 1
      end
    end
  end
end
