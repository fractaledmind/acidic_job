# frozen_string_literal: true

require "test_helper"

def find_or_initialize_child_job(job_class, parent_job_id)
  enqueued_child_job = queue_adapter.enqueued_jobs.find do |it|
    it["job_class"] == job_class.name && it["arguments"].last == parent_job_id
  end
  return ActiveJob::Base.deserialize(enqueued_child_job) if enqueued_child_job

  performed_child_job = queue_adapter.performed_jobs.find do |it|
    it["job_class"] == job_class.name && it["arguments"].last == parent_job_id
  end
  return ActiveJob::Base.deserialize(performed_child_job) if performed_child_job

  job_class.new
end

module Examples
  class AwaitingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      class ChildJob1 < ActiveJob::Base
        attr_accessor :execution

        after_perform do |job|
          job.execution.context[job.job_id] = true
          job.execution.enqueue_job
        end

        def perform(execution, _parent_job_id)
          self.execution = execution
          ChaoticJob.log_to_journal!(serialize)
        end
      end

      class ChildJob2 < ActiveJob::Base
        attr_accessor :execution

        after_perform do |job|
          job.execution.context[job.job_id] = true
          job.execution.enqueue_job
        end

        def perform(execution, _parent_job_id)
          self.execution = execution
          ChaoticJob.log_to_journal!(serialize)
        end
      end

      def perform
        @job_1 = find_or_initialize_child_job(ChildJob1, job_id)
        @job_2 = find_or_initialize_child_job(ChildJob2, job_id)

        execute_workflow(unique_by: job_id) do |w|
          w.step :enqueue_jobs
          w.step :setup_context
          w.step :await_jobs
          w.step :do_something
        end
      end

      def enqueue_jobs
        @job_1.arguments.push execution, job_id
        @job_2.arguments.push execution, job_id
        ActiveJob.perform_all_later(@job_1, @job_2)
      end

      def setup_context
        ctx[:job_ids] = [@job_1.job_id, @job_2.job_id]
      end

      def await_jobs
        ctx[:job_ids].each do |job_id|
          halt_workflow! unless ctx[job_id]
        end
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize)
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # parent job runs 1 time to enqueue children, then once after each child re-enqueues it
      assert_equal 3, performed_jobs.select { |job| job["job_class"] == Job.name }.size
      assert_equal 1, performed_jobs.select { |job| job["job_class"] == Job::ChildJob1.name }.size
      assert_equal 1, performed_jobs.select { |job| job["job_class"] == Job::ChildJob2.name }.size
      assert_equal 5, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 3, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::ChildJob1.name }.size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::ChildJob2.name }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # it takes one halting `await_jobs` step before both child jobs complete
      assert_equal 10, AcidicJob::Entry.count
      assert_equal(
        [
          %w[enqueue_jobs started],
          %w[enqueue_jobs succeeded],
          %w[setup_context started],
          %w[setup_context succeeded],
          %w[await_jobs started],
          %w[await_jobs halted],
          %w[await_jobs started],
          %w[await_jobs succeeded],
          %w[do_something started],
          %w[do_something succeeded],
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # context has 3 values: job_ids, and the truthy values of each job_id
      assert_equal 3, AcidicJob::Value.count
      job_ids = AcidicJob::Value.find_by(key: "job_ids").value

      job_ids.each do |job_id|
        assert AcidicJob::Value.find_by(key: job_id).value
      end
    end

    test "scenario with error before setting up context" do
      run_scenario(Job.new, glitch: ["before", "#{__FILE__}:71"]) do
        perform_all_jobs
      end

      # parent job runs 1 time to enqueue children, 1 time after error, then once after each child re-enqueues it
      assert_equal 4, performed_jobs.select { |job| job["job_class"] == Job.name }.size
      assert_equal 1, performed_jobs.select { |job| job["job_class"] == Job::ChildJob1.name }.size
      assert_equal 1, performed_jobs.select { |job| job["job_class"] == Job::ChildJob2.name }.size
      assert_equal 6, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 3, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::ChildJob1.name }.size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::ChildJob2.name }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # parent job when re-enqueued by children doesn't do any work, just short-circuits since finished
      assert_equal 10, AcidicJob::Entry.count
      assert_equal(
        [
          %w[enqueue_jobs started],
          %w[enqueue_jobs succeeded],
          %w[setup_context started],
          %w[setup_context errored],
          %w[setup_context started],
          %w[setup_context succeeded],
          %w[await_jobs started],
          %w[await_jobs succeeded],
          %w[do_something started],
          %w[do_something succeeded],
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # context has 3 values: job_ids, and the truthy values of each job_id
      assert_equal 3, AcidicJob::Value.count
      job_ids = AcidicJob::Value.find_by(key: "job_ids").value

      job_ids.each do |job_id|
        assert AcidicJob::Value.find_by(key: job_id).value
      end
    end

    test "simulation" do
      run_simulation(Job.new) do |_scenario|
        assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once

        # only performs primary IO operations once per job
        assert_equal 3, ChaoticJob.journal_size
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::ChildJob1.name }.size
        assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::ChildJob2.name }.size
      end
    end
  end
end
