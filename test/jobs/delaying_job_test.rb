# frozen_string_literal: true

require "test_helper"

class DelayingJobTest < ActiveJob::TestCase
  test "workflow runs successfully" do
    future = 14.days.from_now + 1.second

    DelayingJob.perform_later
    perform_all_jobs_within(1.minute)

    # Performed the original job
    assert_equal 1, performed_jobs.size
    assert_equal 1, performed_jobs.select { |job| job["job_class"] == DelayingJob.name }.size
    # Job in 14 days hasn't been executed yet
    assert_equal 1, enqueued_jobs.size
    assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == DelayingJob.name }.size

    # First, test the state of the execution after the first job is halted
    assert_equal 0, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count
    execution = AcidicJob::Execution.first

    # execution is for this job and is paused on the `halt` step
    assert_equal DelayingJob.name, execution.serialized_job["job_class"]
    assert_equal "halt", execution.recover_to

    # nothing happened beyond halting on the `halt` step
    assert_equal 4, AcidicJob::Entry.count
    assert_equal(
      [
        %w[delay started],
        %w[delay succeeded],
        %w[halt started],
        %w[halt halted],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # only one context value for the signal of when to wait until
    assert_equal 1, AcidicJob::Value.count
    wait_until = AcidicJob::Value.find_by(key: :wait_until).value
    assert_in_delta wait_until.to_i, future.to_i, 1, "wait_until: #{wait_until}, but expected #{future}"

    # Now, perform the future scheduled job and check the final state of the execution
    Time.stub :now, future.to_time do
      perform_all_jobs

      assert_equal 2, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # after the halting step, when the future version of the job is performed it completes successfully
      assert_equal 8, AcidicJob::Entry.count
      assert_equal(
        [
          %w[delay started],
          %w[delay succeeded],
          %w[halt started],
          %w[halt halted],
          %w[halt started],
          %w[halt succeeded],
          %w[do_something started],
          %w[do_something succeeded],
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # the most recent job that was performed is the future scheduled job
      assert_equal 1, ChaoticJob.journal_size
      job_that_performed = ChaoticJob.top_journal_entry
      assert_in_delta(
        Time.parse(job_that_performed["scheduled_at"]).to_i,
        future.to_i,
        2,
        "performed job at: #{job_that_performed['scheduled_at']}, but expected #{future}"
      )
    end
  end

  test "scenario with error before halt_workflow!" do
    future = 14.days.from_now + 1.second

    run_scenario(DelayingJob.new, glitch: glitch_before_call("AcidicJob::Workflow#halt_workflow!")) do
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
    assert_equal DelayingJob.name, execution.serialized_job["job_class"]
    assert_equal "halt", execution.recover_to

    # nothing happened beyond erroring then halting on the `halt` step
    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[delay started],
        %w[delay succeeded],
        %w[halt started],
        %w[halt errored],
        %w[halt started],
        %w[halt halted],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # only one context value for the signal of when to wait until
    assert_equal 1, AcidicJob::Value.count
    wait_until = AcidicJob::Value.find_by(key: :wait_until).value
    assert_in_delta wait_until.to_i, future.to_i, 1, "wait_until: #{wait_until}, but expected #{future}"

    # Now, perform the future scheduled job and check the final state of the execution
    Time.stub :now, future.to_time do
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # after the halting step, when the future version of the job is performed it completes successfully
      assert_equal 10, AcidicJob::Entry.count
      assert_equal(
        [
          %w[delay started],
          %w[delay succeeded],
          %w[halt started],
          %w[halt errored],
          %w[halt started],
          %w[halt halted],
          %w[halt started],
          %w[halt succeeded],
          %w[do_something started],
          %w[do_something succeeded],
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

  test "scenario with error before setting wait_until" do
    future = 14.days.from_now + 1.second

    run_scenario(DelayingJob.new, glitch: glitch_before_call("AcidicJob::Context#[]=", :halt, true)) do
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
    assert_equal DelayingJob.name, execution.serialized_job["job_class"]
    assert_equal "halt", execution.recover_to

    # nothing happened beyond erroring then halting on the `halt` step
    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[delay started],
        %w[delay errored],
        %w[delay started],
        %w[delay succeeded],
        %w[halt started],
        %w[halt halted],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # only one context value for the signal of when to wait until
    assert_equal 1, AcidicJob::Value.count
    wait_until = AcidicJob::Value.find_by(key: :wait_until).value
    assert_in_delta wait_until.to_i, future.to_i, 1, "wait_until: #{wait_until}, but expected #{future}"

    # Now, perform the future scheduled job and check the final state of the execution
    Time.stub :now, future.to_time do
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # after the halting step, when the future version of the job is performed it completes successfully
      assert_equal 10, AcidicJob::Entry.count
      assert_equal(
        [
          %w[delay started],
          %w[delay errored],
          %w[delay started],
          %w[delay succeeded],
          %w[halt started],
          %w[halt halted],
          %w[halt started],
          %w[halt succeeded],
          %w[do_something started],
          %w[do_something succeeded],
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

  test "scenario with error before perform returns" do
    future = 14.days.from_now + 1.second

    run_scenario(DelayingJob.new, glitch: glitch_before_return("#{DelayingJob.name}#perform")) do
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
    assert_equal DelayingJob.name, execution.serialized_job["job_class"]
    assert_equal "halt", execution.recover_to

    # nothing happened beyond halting on the `halt` step both the first time and the retry
    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[delay started],
        %w[delay succeeded],
        %w[halt started],
        %w[halt halted],
        %w[halt started],
        %w[halt halted],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # only one context value for the signal of when to wait until
    assert_equal 1, AcidicJob::Value.count
    wait_until = AcidicJob::Value.find_by(key: :wait_until).value
    assert_in_delta wait_until.to_i, future.to_i, 1, "wait_until: #{wait_until}, but expected #{future}"

    # Now, perform the future scheduled job and check the final state of the execution
    Time.stub :now, future.to_time do
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # after the double halts, finally progresses thru `halt` step after job runs in the future
      assert_equal 10, AcidicJob::Entry.count
      assert_equal(
        [
          %w[delay started],
          %w[delay succeeded],
          %w[halt started],
          %w[halt halted],
          %w[halt started],
          %w[halt halted],
          %w[halt started],
          %w[halt succeeded],
          %w[do_something started],
          %w[do_something succeeded],
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

  test_simulation(DelayingJob.new, perform_only_jobs_within: 1.minute) do |_scenario|
    future = 14.days.from_now + 1.second

    # Performed the first job, then retried it
    assert_equal 2, performed_jobs.size
    # Job in 14 days hasn't been executed yet
    assert_includes 1..2, enqueued_jobs.size, foo: "bar"

    # First, test the state of the execution after the first job is halted
    assert_equal 0, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count
    execution = AcidicJob::Execution.first

    # execution is for this job and is paused on the `halt` step
    assert_equal DelayingJob.name, execution.serialized_job["job_class"]
    assert_equal "halt", execution.recover_to

    # Now, perform the future scheduled job and check the final state of the execution
    Time.stub :now, future.to_time do
      perform_all_jobs

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

      # the most recent job that was performed is the future scheduled job
      assert_equal 1, ChaoticJob.journal_size
      job_that_performed = ChaoticJob.top_journal_entry
      assert_in_delta(
        Time.parse(job_that_performed["scheduled_at"]).to_i,
        future.to_i,
        2,
        "performed job at: #{job_that_performed['scheduled_at']}, but expected #{future}"
      )
    end
  end
end