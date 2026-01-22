# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/delay"

module Pro
  class DelayTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :delayed, delay: 14.days
          w.step :do_something
        end
      end

      def delayed
        ChaoticJob.log_to_journal!(serialize)
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize)
      end
    end

    def before_setup
      AcidicJob.plugins << AcidicJob::Plugins::Pro::Delay
      super
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
      assert_equal "delayed", execution.recover_to

      # nothing happened beyond halting on the `halt` step
      assert_equal 3, AcidicJob::Entry.count
      assert_equal(
        [
          %w[delayed started],
          %w[delayed delay/waiting],
          %w[delayed halted],
],
        execution.entries.ordered.pluck(:step, :action)
      )

      # no context values set
      assert_equal 0, AcidicJob::Value.count
      # no step methods have executed yet
      assert_equal 0, ChaoticJob.journal_size

      # Now, perform the future scheduled job and check the final state of the execution
      Time.stub :current, 14.days.from_now.to_time do
        perform_all_jobs

        assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
        execution = AcidicJob::Execution.first

        # after the halting step, when the future version of the job is performed it completes successfully
        assert_equal 7, AcidicJob::Entry.count
        assert_equal(
          [
            %w[delayed started],
            %w[delayed delay/waiting],
            %w[delayed halted],
            %w[delayed started],
            %w[delayed succeeded],
            %w[do_something started],
            %w[do_something succeeded],
],
          execution.entries.ordered.pluck(:step, :action)
        )

        # no context values set
        assert_equal 0, AcidicJob::Value.count
        # both step methods have now executed
        assert_equal 2, ChaoticJob.journal_size

        # the most recent job that was performed is the future scheduled job
        job_that_performed = ChaoticJob.top_journal_entry
        assert_in_delta Time.parse(job_that_performed["scheduled_at"]).to_i, Time.current.to_i, 1, 1
      end
    end

    private def capture_callstack(&block)
      gem_root = AcidicJob::Engine.root.to_s
      tracer = ChaoticJob::Tracer.new { |tp| tp.path.start_with? gem_root }
      tracer.capture(&block)
    end
  end
end
