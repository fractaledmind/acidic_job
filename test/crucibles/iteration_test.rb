# frozen_string_literal: true

require "test_helper"
require "job_crucible"

module Crucibles
  class IterationTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        @enumerable = (1..3).to_a
        execute_workflow(unique_by: job_id) do |w|
          w.step :step_1
        end
      end

      def step_1
        cursor = @ctx[:cursor] || 0
        item = @enumerable[cursor]
        return if item.nil?

        # do thing with `item`
        Performance.performed!

        @ctx[:cursor] = cursor + 1
        repeat_step!
      end
    end

    def before_setup
      Performance.reset!
      AcidicJob::Value.delete_all
      AcidicJob::Entry.delete_all
      AcidicJob::Execution.delete_all
      TestObject.delete_all
    end

    def after_teardown; end

    test "workflow runs successfully" do
      Job.perform_later
      flush_enqueued_jobs until enqueued_jobs.empty?

      assert_equal 3, Performance.performances
      assert_equal 1, AcidicJob::Execution.count

      execution = AcidicJob::Execution.first

      assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
      assert_equal "FINISHED", execution.recover_to

      assert_equal 5, AcidicJob::Entry.count
      assert_equal(
        [%w[step_1 started],
         %w[step_1 started],
         %w[step_1 started],
         %w[step_1 started],
         %w[step_1 succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      assert_equal 1, AcidicJob::Value.count
      assert_equal 3, AcidicJob::Value.first.value
    end

    test "simulation" do
      simulation = JobCrucible::Simulation.new(Job.new, test: self, seed: Minitest.seed, depth: 1)
      simulation.run do |scenario|
        assert_predicate scenario, :all_executed?, scenario.inspect

        execution = AcidicJob::Execution.first

        refute_nil execution.id, scenario.inspect
        assert_equal "FINISHED", execution.recover_to, scenario.inspect

        logs = AcidicJob::Entry.where(execution: execution).order(timestamp: :asc).pluck(:step, :action)

        assert_equal 1, logs.count { |_, action| action == "succeeded" }, scenario.inspect
        # if error occurs during `step_1` step, can have more than 1 start for that step
        assert_operator logs.count { |_, action| action == "started" }, :>=, 4, scenario.inspect
        step_logs = logs.each_with_object({}) { |(step, status), hash| (hash[step] ||= []) << status }

        step_logs.each_value do |actions|
          assert_equal 1, actions.count { |it| it == "succeeded" }, scenario.inspect
        end

        context = AcidicJob::Value.where(execution: execution).order(created_at: :asc).pluck(:key, :value)

        assert_equal 1, context.count, scenario.inspect
        assert_equal [["cursor", 3]], context, scenario.inspect

        assert_equal 7, scenario.events.size, scenario.inspect
        assert_equal(
          ["enqueue.active_job", "perform_start.active_job", "enqueue_at.active_job", "enqueue_retry.active_job",
           "perform.active_job", "perform_start.active_job", "perform.active_job"],
          scenario.events.map(&:name),
          scenario.inspect
        )

        print "."
      end
    end
  end
end
