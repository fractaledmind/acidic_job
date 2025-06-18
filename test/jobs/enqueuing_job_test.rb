# frozen_string_literal: true

require "test_helper"

class EnqueuingJobTest < ActiveJob::TestCase
  test "workflow runs successfully" do
    EnqueuingJob.perform_later
    perform_all_jobs

    # Performed the job and the enqueued job
    assert_equal 2, performed_jobs.size
    assert_equal 0, enqueued_jobs.size

    # only performs primary IO operations once per job
    assert_equal 2, ChaoticJob.journal_size
    assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == EnqueuingJob.name }.size
    assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == EnqueuedJob.name }.size

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    # simple walkthrough of the execution
    assert_equal 4, AcidicJob::Entry.count
    assert_equal(
      [
        %w[enqueue_job started],
        %w[enqueue_job succeeded],
        %w[do_something started],
        %w[do_something succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # context has 2 values: child job and the truthy value of the child job
    assert_equal 2, AcidicJob::Value.count
    child_job = AcidicJob::Value.find_by(key: :child_job).value
    assert AcidicJob::Value.find_by(key: child_job.job_id).value
  end

  test "scenario with error after enqueuing job" do
    run_scenario(EnqueuingJob.new, glitch: glitch_before_return("#{EnqueuingJob.name}#enqueue_job")) do
      perform_all_jobs

      # Performed the parent job, its retry, and the child job
      assert_equal 3, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # performs primary IO operation once per iteration
      assert_equal 2, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == EnqueuingJob.name }.size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == EnqueuedJob.name }.size

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # iterates over 3 item array before succeeding
      assert_equal 6, AcidicJob::Entry.count
      assert_equal(
        [
          %w[enqueue_job started],
          %w[enqueue_job errored],
          %w[enqueue_job started],
          %w[enqueue_job succeeded],
          %w[do_something started],
          %w[do_something succeeded]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # context has 2 values: child job and the truthy value of the child job
      assert_equal 2, AcidicJob::Value.count
      child_job = AcidicJob::Value.find_by(key: :child_job).value
      assert AcidicJob::Value.find_by(key: child_job.job_id).value
    end
  end

  test_simulation(EnqueuingJob.new) do |_scenario|
    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

    # only performs primary IO operations once per job
    assert_equal 2, ChaoticJob.journal_size, ChaoticJob.journal_entries
    assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == EnqueuingJob.name }.size
    assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == EnqueuedJob.name }.size
  end
end
