# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/check"

module Pro
  class CheckTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :do_something, check: { every: 2.minutes, until: :conditional }
        end
      end

      def conditional
        executions == 3
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize)
      end
    end

    def before_setup
      AcidicJob.plugins << AcidicJob::Plugins::Pro::Check
      super
    end

    test "workflow runs successfully" do
      Job.perform_later

      # first run
      Time.stub :now, Time.now do
        perform_all_jobs_within(1.minute.from_now)

        # Performed the original job
        assert_equal 1, performed_jobs.select { |job| job["job_class"] == Job.name }.size
        # Retry in 2 minutes hasn't been executed yet
        assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == Job.name }.size
        assert_equal 1, performed_jobs.size
        assert_equal 1, enqueued_jobs.size

        # execution is for this job and is paused on the `delayed` step
        execution = AcidicJob::Execution.first
        assert_equal Job.name, execution.serialized_job["job_class"]
        assert_equal "do_something", execution.recover_to

        # nothing happened beyond halting on the `delayed` step
        assert_equal 3, AcidicJob::Entry.count
        assert_equal(
          [
            %w[do_something started],
            %w[do_something check/waiting],
            %w[do_something halted],
          ],
          execution.entries.ordered.pluck(:step, :action)
        )

        # no step methods have executed
        assert_equal 0, ChaoticJob.journal_size
      end

      # First retry
      Time.stub :now, 2.minutes.from_now.to_time do
        perform_all_jobs_within(1.minute.from_now)

        # Performed the original job and the first retry
        assert_equal 2, performed_jobs.select { |job| job["job_class"] == Job.name }.size
        # Next retry in 2 minutes hasn't been executed yet
        assert_equal 1, enqueued_jobs.select { |job| job["job_class"] == Job.name }.size
        assert_equal 2, performed_jobs.size
        assert_equal 1, enqueued_jobs.size

        # execution is for this job and is still paused on the `delayed` step
        execution = AcidicJob::Execution.first
        assert_equal Job.name, execution.serialized_job["job_class"]
        assert_equal "do_something", execution.recover_to

        # nothing happened beyond halting on the `delayed` step
        assert_equal 6, AcidicJob::Entry.count
        assert_equal(
          [
            %w[do_something started],
            %w[do_something check/waiting],
            %w[do_something halted],
            %w[do_something started],
            %w[do_something check/waiting],
            %w[do_something halted],
          ],
          execution.entries.ordered.pluck(:step, :action)
        )

        # no step methods have executed
        assert_equal 0, ChaoticJob.journal_size
      end

      # Final retry
      Time.stub :now, 4.minutes.from_now.to_time do
        perform_all_jobs_within(1.minute.from_now)

        # Performed the original job, first retry, and final retry
        assert_equal 3, performed_jobs.select { |job| job["job_class"] == Job.name }.size
        # No more retries, job done
        assert_equal 0, enqueued_jobs.select { |job| job["job_class"] == Job.name }.size
        assert_equal 3, performed_jobs.size
        assert_equal 0, enqueued_jobs.size

        # job is finished successfully
        assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
        execution = AcidicJob::Execution.first

        # nothing happened beyond halting on the `delayed` step
        assert_equal 8, AcidicJob::Entry.count
        assert_equal(
          [
            %w[do_something started],
            %w[do_something check/waiting],
            %w[do_something halted],
            %w[do_something started],
            %w[do_something check/waiting],
            %w[do_something halted],
            %w[do_something started],
            %w[do_something succeeded],
          ],
          execution.entries.ordered.pluck(:step, :action)
        )

        # step method has now executed
        assert_equal 1, ChaoticJob.journal_size
      end
    end

    private def capture_callstack(&block)
      gem_root = AcidicJob::Engine.root.to_s
      tracer = ChaoticJob::Tracer.new { |tp| tp.path.start_with? gem_root }
      tracer.capture(&block)
    end
  end
end
