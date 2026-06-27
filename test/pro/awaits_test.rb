# frozen_string_literal: true

require "test_helper"
require "acidic_job/plugins/pro/awaits"

# Register at load time (not in `before_setup`) so the plugin is active during
# `test_simulation`'s callstack capture, which runs when the class is defined.
unless AcidicJob.plugins.include?(AcidicJob::Plugins::Pro::Awaits)
  AcidicJob.plugins << AcidicJob::Plugins::Pro::Awaits
end

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
          w.step :do_something, awaits: :awaited_jobs
        end
      end

      def awaited_jobs
        [ AwaitedJob.new, AwaitedJob.new ]
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

      # parent job runs once to enqueue children and halt, then once more after all children complete
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == Job::AwaitedJob.name }.size
      assert_equal 4, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 3, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job.name }.size
      assert_equal 2, ChaoticJob::Journal.entries.select { |job| job["job_class"] == Job::AwaitedJob.name }.size

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # it takes one halting `awaits` step before the children jobs complete
      assert_equal 5, AcidicJob::Entry.count
      assert_equal(
        [
          %w[do_something started],
          %w[do_something awaits/awaiting],
          %w[do_something halted],
          %w[do_something started],
          %w[do_something succeeded]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # context has 3 values: job_ids array and both child job completion records
      assert_equal 3, AcidicJob::Value.count
      job_ids = AcidicJob::Value.find_by(key: "job_ids").value
      job_ids.each do |job_id|
        value_record = AcidicJob::Value.find_by(key: job_id)
        assert value_record.value["completed"], "Expected job #{job_id} to be marked as completed"
      end
    end

    # ============================================
    # Edge cases & failure scenarios
    # ============================================

    class EmptyAwaitsJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :do_something, awaits: :no_jobs
        end
      end

      def no_jobs
        []
      end

      def do_something
        ChaoticJob.log_to_journal!(:done)
      end
    end

    test "proceeds immediately when there are no jobs to await" do
      EmptyAwaitsJob.perform_later
      perform_all_jobs

      # the workflow must NOT halt forever — with no children, nothing would ever
      # re-enqueue it
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      assert_equal [ :done ], ChaoticJob::Journal.entries
    end

    test "self-heals when a crash interrupts before the awaited jobs are enqueued" do
      run_scenario(
        Job.new,
        glitch: glitch_before_call("ActiveJob.perform_all_later")
      ) do
        perform_all_jobs
      end

      # despite the crash before the first enqueue, both children ran and the
      # parent completed (the old code would have yielded the body early on retry)
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      assert_equal 3, ChaoticJob.journal_size
      assert_equal 1, ChaoticJob::Journal.entries.count { |e| e["job_class"] == Job.name }
      assert_equal 2, ChaoticJob::Journal.entries.count { |e| e["job_class"] == Job::AwaitedJob.name }
    end

    class SimJob < ActiveJob::Base
      include AcidicJob::Workflow

      class Child < ActiveJob::Base
        include AcidicJob::Workflow

        def perform(n)
          # idempotent: keyed on the argument, stable across replays
          ChaoticJob.log_to_journal!("child-#{n}")
        end
      end

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :do_something, awaits: :children
        end
      end

      def children
        [ Child.new(1), Child.new(2) ]
      end

      def do_something
        ChaoticJob.log_to_journal!(:parent_done)
      end
    end

    test_simulation(SimJob.new) do |_scenario|
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

      # regardless of where a failure is injected, both children run and the
      # parent's body runs, exactly once each
      assert_equal 3, ChaoticJob.journal_size
      assert_includes ChaoticJob::Journal.entries, :parent_done
      assert_includes ChaoticJob::Journal.entries, "child-1"
      assert_includes ChaoticJob::Journal.entries, "child-2"
    end
  end
end
