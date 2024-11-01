# frozen_string_literal: true

require "test_helper"
require "job_crucible"

module Crucibles
  class DelayingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :delay
          w.step :do_something
        end
      end

      def delay
        new_job = self.class.new(*arguments)
        new_job.job_id = job_id
        # new_job.provider_job_id = provider_job_id
        new_job.enqueue(wait: 14.days)
        @ctx[:halt] = true
      end

      def do_something
        if @ctx[:halt]
          @ctx[:halt] = false
          halt_step!
        end
        Performance.performed!
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

      assert_equal 1, Performance.performances
      assert_equal 1, AcidicJob::Execution.count

      execution = AcidicJob::Execution.first

      assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
      assert_equal "FINISHED", execution.recover_to

      assert_equal 6, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[do_something started],
         %w[do_something halted],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      assert_equal 1, AcidicJob::Value.count
      refute AcidicJob::Value.find_by(key: "halt").value
    end

    test "simulation" do
      job = Job.new
      simulation = JobCrucible::Simulation.new(job, seed: Minitest.seed, depth: 1)
      simulation.run do |scenario|
        assert_predicate scenario, :all_executed?, scenario.inspect

        execution_id, recover_to = AcidicJob::Execution.where(idempotency_key: job.idempotency_key)
                                                       .pick(:id, :recover_to)

        refute_nil execution_id, scenario.inspect
        assert_equal "FINISHED", recover_to, scenario.inspect

        logs = AcidicJob::Entry.where(execution_id: execution_id).order(timestamp: :asc).pluck(:step, :action)

        assert_equal 2, logs.count { |_, action| action == "succeeded" }, scenario.inspect
        assert_equal 3, logs.count { |_, action| action == "started" }, scenario.inspect
        step_logs = logs.each_with_object({}) { |(step, status), hash| (hash[step] ||= []) << status }

        step_logs.each_value do |actions|
          assert_equal 1, actions.count { |it| it == "succeeded" }, scenario.inspect
        end

        context = AcidicJob::Value.where(execution_id: execution_id).order(created_at: :asc).pluck(:key, :value)

        assert_equal 1, context.count, scenario.inspect
        assert_equal false, AcidicJob::Value.find_by(key: "halt").value, scenario.inspect

        assert_operator scenario.events.size, :>=, 10, scenario.inspect

        print "."
      end
    end
  end
end
