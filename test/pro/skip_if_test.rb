# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/skip_if"

module Pro
  class SkipIfTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :skip_me, skip_if: :truthy
          w.step :do_something, skip_if: :falsey
        end
      end

      def truthy
        true
      end

      def falsey
        false
      end

      def skip_me
        ChaoticJob.log_to_journal!(:skip_me)
      end

      def do_something
        ChaoticJob.log_to_journal!(:do_something)
      end
    end

    def before_setup
      AcidicJob.plugins << AcidicJob::Plugins::Pro::SkipIf
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
          %w[skip_me started],
          %w[skip_me skip_if/skipping],
          %w[skip_me succeeded],
          %w[do_something started],
          %w[do_something succeeded],
],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only the `do_something` step method was executed
      assert_equal 1, ChaoticJob.journal_size
      assert_equal :do_something, ChaoticJob.top_journal_entry
    end
  end
end
