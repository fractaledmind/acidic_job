# frozen_string_literal: true

require "test_helper"

class WaitingJobTest < ActiveJob::TestCase
  def before_setup
    ChaoticJob.switch_off!
    super
  end

  test "workflow runs successfully" do
    WaitingJob.perform_later

    # first run
    Time.stub :now, Time.now do
      perform_all_jobs_within(1.minute)

      # Performed the original job
      assert_equal 1, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # Retry in 2 minutes hasn't been executed yet
      assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 1, performed_jobs.size
      assert_equal 1, enqueued_jobs.size

      # execution is for this job and is paused on the `delayed` step
      execution = AcidicJob::Execution.first
      assert_equal WaitingJob.name, execution.serialized_job["job_class"]
      assert_equal "check", execution.recover_to

      # nothing happened beyond halting on the `delayed` step
      assert_equal 2, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # no step methods have executed
      assert_equal 0, ChaoticJob.journal_size
    end

    # First retry
    Time.stub :now, 2.days.from_now.to_time do
      perform_all_jobs_within(1.minute.from_now)

      # Performed the original job and the first retry
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # Next retry in 2 minutes hasn't been executed yet
      assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 2, performed_jobs.size
      assert_equal 1, enqueued_jobs.size

      # execution is for this job and is still paused on the `delayed` step
      execution = AcidicJob::Execution.first
      assert_equal WaitingJob.name, execution.serialized_job["job_class"]
      assert_equal "check", execution.recover_to

      # nothing happened beyond halting on the `delayed` step
      assert_equal 4, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check halted]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # no step methods have executed
      assert_equal 0, ChaoticJob.journal_size
    end

    # Final retry
    future = 4.days.from_now
    Time.stub :now, future.to_time do
      ChaoticJob.switch_on!
      perform_all_jobs

      # Performed the original job, first retry, and final retry
      assert_equal 3, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # No more retries, job done
      assert_equal 0, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 3, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # job is finished successfully
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # nothing happened beyond halting on the `delayed` step
      assert_equal 8, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check succeeded],
          %w[do_something started],
          %w[do_something succeeded]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # the most recent job that was performed is the future scheduled job
      assert_equal 1, ChaoticJob.journal_size
      job_that_performed = ChaoticJob.top_journal_entry
      assert_in_delta(
        Time.parse(job_that_performed["scheduled_at"]).to_i,
        future.to_i,
        1,
        "performed job at: #{job_that_performed['scheduled_at']}, but expected #{future}"
      )
    end
  end

  test "scenario before call perform" do
    run_scenario(WaitingJob.new, glitch: glitch_before_call("#{WaitingJob.name}#perform")) do
      perform_all_jobs_within(1.minute)
    end

    # first run
    begin
      # Performed the original job and the retry
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # Retry in 2 minutes hasn't been executed yet
      assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 2, performed_jobs.size
      assert_equal 1, enqueued_jobs.size

      # execution is for this job and is paused on the `delayed` step
      execution = AcidicJob::Execution.first
      assert_equal WaitingJob.name, execution.serialized_job["job_class"]
      assert_equal "check", execution.recover_to

      # nothing happened beyond halting on the `delayed` step
      assert_equal 2, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # no step methods have executed
      assert_equal 0, ChaoticJob.journal_size
    end

    # First retry
    Time.stub :now, 2.days.from_now.to_time do
      perform_all_jobs_within(1.minute.from_now)

      # Performed the original job, the retry, and the first wait
      assert_equal 3, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # Next retry in 2 minutes hasn't been executed yet
      assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 3, performed_jobs.size
      assert_equal 1, enqueued_jobs.size

      # execution is for this job and is still paused on the `delayed` step
      execution = AcidicJob::Execution.first
      assert_equal WaitingJob.name, execution.serialized_job["job_class"]
      assert_equal "check", execution.recover_to

      # nothing happened beyond halting on the `delayed` step
      assert_equal 4, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check halted]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # no step methods have executed
      assert_equal 0, ChaoticJob.journal_size
    end

    # Final retry
    future = 4.days.from_now
    Time.stub :now, future.to_time do
      ChaoticJob.switch_on!
      perform_all_jobs

      # Performed the original job, the retry, the first wait, and the second wait
      assert_equal 4, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # No more retries, job done
      assert_equal 0, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 4, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # job is finished successfully
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # nothing happened beyond halting on the `delayed` step
      assert_equal 8, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check succeeded],
          %w[do_something started],
          %w[do_something succeeded]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # the most recent job that was performed is the future scheduled job
      assert_equal 1, ChaoticJob.journal_size
      job_that_performed = ChaoticJob.top_journal_entry
      assert_in_delta(
        Time.parse(job_that_performed["scheduled_at"]).to_i,
        future.to_i,
        1,
        "performed job at: #{job_that_performed['scheduled_at']}, but expected #{future}"
      )
    end
  end

  test "scenario before call do_something" do
    run_scenario(WaitingJob.new, glitch: glitch_before_call("#{WaitingJob.name}#do_something")) do
      perform_all_jobs_within(1.minute)
    end

    # first run
    begin
      # Performed the original job
      assert_equal 1, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # Retry in 2 minutes hasn't been executed yet
      assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 1, performed_jobs.size
      assert_equal 1, enqueued_jobs.size

      # execution is for this job and is paused on the `delayed` step
      execution = AcidicJob::Execution.first
      assert_equal WaitingJob.name, execution.serialized_job["job_class"]
      assert_equal "check", execution.recover_to

      # nothing happened beyond halting on the `delayed` step
      assert_equal 2, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # no step methods have executed
      assert_equal 0, ChaoticJob.journal_size
    end

    # First retry
    Time.stub :now, 2.days.from_now.to_time do
      perform_all_jobs_within(1.minute.from_now)

      # Performed the original job, and the first wait
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # Next retry in 2 minutes hasn't been executed yet
      assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 2, performed_jobs.size
      assert_equal 1, enqueued_jobs.size

      # execution is for this job and is still paused on the `delayed` step
      execution = AcidicJob::Execution.first
      assert_equal WaitingJob.name, execution.serialized_job["job_class"]
      assert_equal "check", execution.recover_to

      # nothing happened beyond halting on the `delayed` step
      assert_equal 4, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check halted]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # no step methods have executed
      assert_equal 0, ChaoticJob.journal_size
    end

    # Final retry
    future = 4.days.from_now
    Time.stub :now, future.to_time do
      ChaoticJob.switch_on!
      perform_all_jobs

      # Performed the original job, the first wait, and the second wait
      assert_equal 3, performed_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      # No more retries, job done
      assert_equal 0, enqueued_jobs.select { |job| job["job_class"] == WaitingJob.name }.size
      assert_equal 3, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # job is finished successfully
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # nothing happened beyond halting on the `delayed` step
      assert_equal 8, AcidicJob::Entry.count
      assert_equal(
        [
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check halted],
          %w[check started],
          %w[check succeeded],
          %w[do_something started],
          %w[do_something succeeded]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # the most recent job that was performed is the future scheduled job
      assert_equal 1, ChaoticJob.journal_size
      job_that_performed = ChaoticJob.top_journal_entry
      assert_in_delta(
        Time.parse(job_that_performed["scheduled_at"]).to_i,
        future.to_i,
        1,
        "performed job at: #{job_that_performed['scheduled_at']}, but expected #{future}"
      )
    end
  end

  test_simulation(WaitingJob.new, perform_only_jobs_within: 1.minute) do |_scenario|
    # first run
    begin
      first_run_performances = performed_jobs.size
      assert_operator first_run_performances, :>, 0
      # execution is for this job and is paused on the `check` step
      execution = AcidicJob::Execution.first
      assert_equal WaitingJob.name, execution.serialized_job["job_class"]
      assert_equal "check", execution.recover_to

      # no step methods have executed
      assert_equal 0, ChaoticJob.journal_size
    end

    # First retry
    Time.stub :now, 2.days.from_now.to_time do
      perform_all_jobs_within(1.minute)

      assert_operator performed_jobs.size, :>, first_run_performances

      # execution is for this job and is still paused on the `check` step
      execution = AcidicJob::Execution.first
      assert_equal WaitingJob.name, execution.serialized_job["job_class"]
      assert_equal "check", execution.recover_to

      # no step methods have executed
      assert_equal 0, ChaoticJob.journal_size
    end

    future = 4.days.from_now
    Time.stub :now, future.to_time do
      ChaoticJob.switch_on!
      perform_all_jobs

      assert_operator performed_jobs.size, :>, first_run_performances

      # job is finished successfully
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # the most recent job that was performed is the future scheduled job
      assert_includes 1..2, ChaoticJob.journal_size, ChaoticJob.journal_entries
      job_that_performed = ChaoticJob.top_journal_entry
      assert_in_delta(
        Time.parse(job_that_performed["scheduled_at"]).to_i,
        future.to_i,
        1,
        "performed job at: #{job_that_performed['scheduled_at']}, but expected #{future}"
      )
    end
  end
end
