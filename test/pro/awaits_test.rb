# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/awaits"

module Pro
  class AwaitsTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      class AwaitedJob < ActiveJob::Base
        include AcidicJob::Workflow

        def perform
          ChaoticJob.log_to_journal!(serialize)
        end
      end

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :do_something, awaits: [AwaitedJob.new, AwaitedJob.new]
        end
      end

      def do_something
        # idempotent because journal logging is idempotent via Set
        # but this means data logged must be identical across executions
        ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
      end
    end

    def before_setup
      AcidicJob.plugins << AcidicJob::Plugins::Pro::Awaits
      super
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

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # it takes one halting `await_jobs` step before the children jobs complete
      assert_equal 5, AcidicJob::Entry.count
      assert_equal(
        [
          %w[do_something started],
          %w[do_something awaits/awaiting],
          %w[do_something halted],
          %w[do_something started],
          %w[do_something succeeded],
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # context has 5 values: job_ids, both children jobs, and the truthy values of each job_id
      assert_equal 3, AcidicJob::Value.count
      job_ids = AcidicJob::Value.find_by(key: :job_ids).value
      job_ids.each do |job_id|
        assert AcidicJob::Value.find_by(key: job_id).value
      end
    end
  end
end
