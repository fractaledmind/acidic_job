# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/compensate"

CustomError = Class.new(StandardError)

module Pro
  class CompensateTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :erroring, compensate: { on: CustomError, with: :compensation }
          w.step :do_something
        end
      end

      def compensation
        ChaoticJob.log_to_journal!(:compensated)
      end

      def erroring
        raise CustomError
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize)
      end
    end

    def before_setup
      AcidicJob.plugins << AcidicJob::Plugins::Pro::Compensate
      super
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # Performed only the job
      assert_equal 1, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # job is finished successfully
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # nothing happened beyond halting on the `delayed` step
      assert_equal 5, AcidicJob::Entry.count
      assert_equal(
        [
          %w[erroring started],
          %w[erroring compensate/compensating],
          %w[erroring succeeded],
          %w[do_something started],
          %w[do_something succeeded],
],
        execution.entries.ordered.pluck(:step, :action)
      )

      # both the step method and the compensation method have executed
      assert_equal 2, ChaoticJob.journal_size
      assert_equal :compensated, ChaoticJob.top_journal_entry
    end
  end
end
