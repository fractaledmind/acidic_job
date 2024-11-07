# frozen_string_literal: true

require "test_helper"

module Crucibles
  class WaitingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :wait_until
          w.step :do_something
        end
      end

      def wait_until
        return if step_retrying?

        enqueue(wait: 2.seconds)

        halt_step!
      end

      def do_something
        ChaoticJob.log_to_journal!
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all

      assert_equal 1, ChaoticJob.journal_size
      assert_equal 1, AcidicJob::Execution.count

      execution = AcidicJob::Execution.first

      assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
      assert_equal "FINISHED", execution.recover_to

      assert_equal 6, AcidicJob::Entry.count
      assert_equal(
        [%w[wait_until started],
         %w[wait_until halted],
         %w[wait_until started],
         %w[wait_until succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      assert_equal 0, AcidicJob::Value.count
    end

    test "simulation" do
      run_simulation(Job.new) do |scenario|
        execution = AcidicJob::Execution.first

        refute_nil execution.id, scenario.inspect
        assert_equal "FINISHED", execution.recover_to, scenario.inspect

        logs = AcidicJob::Entry.where(execution: execution).order(timestamp: :asc).pluck(:step, :action)

        assert_equal 2, logs.count { |_, action| action == "succeeded" }, scenario.inspect
        assert_equal 3, logs.count { |_, action| action == "started" }, scenario.inspect
        step_logs = logs.each_with_object({}) { |(step, status), hash| (hash[step] ||= []) << status }

        step_logs.each_value do |actions|
          assert_equal 1, actions.count { |it| it == "succeeded" }, scenario.inspect
        end

        context = AcidicJob::Value.where(execution: execution).order(created_at: :asc).pluck(:key, :value)

        assert_equal 0, context.count, scenario.inspect
        assert_operator scenario.events.size, :>=, 7, scenario.inspect
      end
    end
  end
end
