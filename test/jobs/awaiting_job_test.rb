# frozen_string_literal: true

require "test_helper"

class AwaitingJobTest < ActiveJob::TestCase
  test "workflow runs successfully" do
    AwaitingJob.perform_later
    perform_all_jobs

    # parent job runs 1 time to enqueue children, then once after each child re-enqueues it
    assert_equal 3, performed_jobs.select { |job| job["job_class"] == AwaitingJob.name }.size
    assert_equal 2, performed_jobs.select { |job| job["job_class"] == AwaitedJob.name }.size
    assert_equal 5, performed_jobs.size
    assert_equal 0, enqueued_jobs.size

    # only performs primary IO operations once per job
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == AwaitingJob.name }.size
    assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == AwaitedJob.name }.size

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    # it takes one halting `await_jobs` step before the children jobs complete
    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [
        %w[enqueue_jobs started],
        %w[enqueue_jobs succeeded],
        %w[await_jobs started],
        %w[await_jobs halted],
        %w[await_jobs started],
        %w[await_jobs succeeded],
        %w[do_something started],
        %w[do_something succeeded],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # context has 5 values: job_ids, both children jobs, and the truthy values of each job_id
    assert_equal 5, AcidicJob::Value.count
    job_ids = AcidicJob::Value.find_by(key: :job_ids).value
    job_ids.each do |job_id|
      assert AcidicJob::Value.find_by(key: job_id).value
    end
  end

  test "scenario with error before setting up context" do
    run_scenario(AwaitingJob.new, glitch: glitch_before_call("AcidicJob::Context#[]=", :job_ids, Array)) do
      perform_all_jobs
    end

    # parent job runs 1 time to enqueue children, 1 time after error, then once after each child re-enqueues it
    assert_equal 4, performed_jobs.select { |job| job["job_class"] == AwaitingJob.name }.size
    assert_equal 2, performed_jobs.select { |job| job["job_class"] == AwaitedJob.name }.size
    assert_equal 6, performed_jobs.size
    assert_equal 0, enqueued_jobs.size

    # only performs primary IO operations once per job
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == AwaitingJob.name }.size
    assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == AwaitedJob.name }.size

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    # parent job when re-enqueued by children doesn't do any work, just short-circuits since finished
    assert_equal 10, AcidicJob::Entry.count
    assert_equal(
      [
        %w[enqueue_jobs started],
        %w[enqueue_jobs errored],
        %w[enqueue_jobs started],
        %w[enqueue_jobs succeeded],
        %w[await_jobs started],
        %w[await_jobs halted],
        %w[await_jobs started],
        %w[await_jobs succeeded],
        %w[do_something started],
        %w[do_something succeeded],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # context has 5 values: job_ids, both children jobs, and the truthy values of each job_id
    assert_equal 5, AcidicJob::Value.count
    job_ids = AcidicJob::Value.find_by(key: "job_ids").value
    job_ids.each do |job_id|
      assert AcidicJob::Value.find_by(key: job_id).value
    end
  end

  test "scenario with error before enqueuing jobs returns" do
    run_scenario(AwaitingJob.new, glitch: glitch_before_return("AwaitingJob#enqueue_jobs")) do
      perform_all_jobs
    end

    # parent job runs 1 time to enqueue children, 1 time after error, then once after each child re-enqueues it
    assert_equal 4, performed_jobs.select { |job| job["job_class"] == AwaitingJob.name }.size
    assert_equal 2, performed_jobs.select { |job| job["job_class"] == AwaitedJob.name }.size
    assert_equal 6, performed_jobs.size
    assert_equal 0, enqueued_jobs.size

    # only performs primary IO operations once per job
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == AwaitingJob.name }.size
    assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == AwaitedJob.name }.size

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    # parent job when re-enqueued by children doesn't do any work, just short-circuits since finished
    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [
        %w[enqueue_jobs started],
        %w[enqueue_jobs errored],
        %w[enqueue_jobs started],
        %w[enqueue_jobs succeeded],
        %w[await_jobs started],
        %w[await_jobs succeeded],
        %w[do_something started],
        %w[do_something succeeded],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # context has 5 values: job_ids, both children jobs, and the truthy values of each job_id
    assert_equal 5, AcidicJob::Value.count
    job_ids = AcidicJob::Value.find_by(key: "job_ids").value
    job_ids.each do |job_id|
      assert AcidicJob::Value.find_by(key: job_id).value
    end
  end

  test_simulation(AwaitingJob.new) do |_scenario|
    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

    # only performs primary IO operations once per job
    assert_equal(
      ["AwaitedJob", "AwaitedJob", "AwaitingJob"],
      ChaoticJob.journal_entries.map { |entry| entry["job_class"] }
    )
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == AwaitingJob.name }.size
    assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == AwaitedJob.name }.size
  end
end
