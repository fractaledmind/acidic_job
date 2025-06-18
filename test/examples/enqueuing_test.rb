# frozen_string_literal: true

require "test_helper"

module Examples
  class EnqueuingTest < ActiveJob::TestCase
    class ChildJob < ActiveJob::Base
      attr_accessor :execution

      after_perform do |job|
        job.execution.context[job.job_id] = true
      end

      def perform(execution)
        self.execution = execution
        # idempotent because journal logging is idempotent via Set
        # but this means data logged must be identical across executions
        ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
      end
    end

    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :enqueue_job
          w.step :do_something
        end
      end

      def enqueue_job
        child_job = ctx.fetch(:child_job) { ChildJob.new(execution) }

        return if ctx[child_job.job_id]

        ActiveJob.perform_all_later(child_job)
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

      # Performed the job and the enqueued job
      assert_equal 2, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 2, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == ChildJob.name }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # simple walkthrough of the execution
      assert_equal 4, AcidicJob::Entry.count
      assert_equal(
        [
          %w[enqueue_job started],
          %w[enqueue_job succeeded],
          %w[do_something started],
          %w[do_something succeeded],
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # context has 2 values: child job and the truthy value of the child job
      assert_equal 2, AcidicJob::Value.count
      child_job = AcidicJob::Value.find_by(key: :child_job).value
      assert AcidicJob::Value.find_by(key: child_job.job_id).value
    end

    test "scenario with error after enqueuing job" do
      run_scenario(Job.new, glitch: glitch_before_return("#{Job.name}#enqueue_job")) do
        perform_all_jobs

        # Performed the parent job, its retry, and the child job
        assert_equal 3, performed_jobs.size
        assert_equal 0, enqueued_jobs.size

        # performs primary IO operation once per iteration
        assert_equal 2, ChaoticJob.journal_size
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == ChildJob.name }.size

        assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
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
            %w[do_something succeeded],
          ],
          execution.entries.ordered.pluck(:step, :action)
        )

        # context has 2 values: child job and the truthy value of the child job
        assert_equal 2, AcidicJob::Value.count
        child_job = AcidicJob::Value.find_by(key: :child_job).value
        assert AcidicJob::Value.find_by(key: child_job.job_id).value
      end
    end

    test_simulation(Job.new) do |_scenario|
      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once

      # only performs primary IO operations once per job
      assert_equal 2, ChaoticJob.journal_size, ChaoticJob.journal_entries
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == ChildJob.name }.size
    end
  end
end
