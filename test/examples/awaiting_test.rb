# frozen_string_literal: true

require "test_helper"

module Examples
  class AwaitingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      class AwaitedJob < ActiveJob::Base
        attr_accessor :execution

        after_perform do |job|
          job.execution.context[job.job_id] = true
          job.execution.enqueue_job
        end

        def perform(execution)
          self.execution = execution
          ChaoticJob.log_to_journal!(serialize)
        end
      end

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :enqueue_jobs
          w.step :await_jobs
          w.step :do_something
        end
      end

      def enqueue_jobs
        @awaited_job_1 = ctx.fetch(:awaited_job_1) { AwaitedJob.new(execution) }
        @awaited_job_2 = ctx.fetch(:awaited_job_2) { AwaitedJob.new(execution) }

        return if ctx[@awaited_job_1.job_id] || ctx[@awaited_job_2.job_id]

        ctx[:job_ids] = [@awaited_job_1.job_id, @awaited_job_2.job_id]
        ActiveJob.perform_all_later(@awaited_job_1, @awaited_job_2)
      end

      def await_jobs
        ctx[:job_ids].each do |job_id|
          halt_workflow! unless ctx[job_id]
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

      # parent job runs 1 time to enqueue children, then once after each child re-enqueues it
      assert_equal 3, performed_jobs.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == Job::AwaitedJob.name }.size
      assert_equal 5, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 3, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::AwaitedJob.name }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
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
      run_scenario(Job.new, glitch: glitch_before_call("AcidicJob::Context#[]=", :job_ids, Array)) do
        perform_all_jobs
      end

      # parent job runs 1 time to enqueue children, 1 time after error, then once after each child re-enqueues it
      assert_equal 4, performed_jobs.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == Job::AwaitedJob.name }.size
      assert_equal 6, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 3, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::AwaitedJob.name }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
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
      job_ids = AcidicJob::Value.find_by(key: :job_ids).value
      job_ids.each do |job_id|
        assert AcidicJob::Value.find_by(key: job_id).value
      end
    end

    test "scenario with error before enqueuing jobs returns" do
      run_scenario(Job.new, glitch: glitch_before_return("#{Job.name}#enqueue_jobs")) do
        perform_all_jobs
      end

      # parent job runs 1 time to enqueue children, 1 time after error, then once after each child re-enqueues it
      assert_equal 4, performed_jobs.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == Job::AwaitedJob.name }.size
      assert_equal 6, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 3, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::AwaitedJob.name }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
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
      job_ids = AcidicJob::Value.find_by(key: :job_ids).value
      job_ids.each do |job_id|
        assert AcidicJob::Value.find_by(key: job_id).value
      end
    end

    test_simulation(Job.new) do |_scenario|
      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once

      # only performs primary IO operations once per job
      assert_equal(
        [Job::AwaitedJob.name, Job::AwaitedJob.name, Job.name],
        ChaoticJob.journal_entries.map { |entry| entry["job_class"] }
      )
      assert_equal 3, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::AwaitedJob.name }.size
    end
  end
end
