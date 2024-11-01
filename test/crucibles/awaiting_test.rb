# frozen_string_literal: true

require "test_helper"
require "job_crucible"

module Crucibles
  class AwaitingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      class ChildJob1 < ActiveJob::Base
        attr_accessor :execution

        after_perform do |job|
          job.execution.context[job.job_id] = true
          job.execution.enqueue_job
        end

        def perform(execution)
          self.execution = execution
          Performance.performed!
        end
      end

      class ChildJob2 < ActiveJob::Base
        attr_accessor :execution

        after_perform do |job|
          job.execution.context[job.job_id] = true
          job.execution.enqueue_job
        end

        def perform(execution)
          self.execution = execution
          Performance.performed!
        end
      end

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :enqueue_jobs
          w.step :await_jobs
          w.step :do_something
        end
      end

      def enqueue_jobs
        job_1 = ChildJob1.new(@execution)
        job_2 = ChildJob2.new(@execution)
        job_1.enqueue
        job_2.enqueue
        # ActiveJob.perform_all_later(job_1, job_2)

        @ctx[:job_ids] = [job_1.job_id, job_2.job_id]
        @ctx[job_1.job_id] = false
        @ctx[job_2.job_id] = false
      end

      def await_jobs
        @ctx[:job_ids].each do |job_id|
          halt_step! unless @ctx[job_id]
        end
      end

      def do_something
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

      assert_equal 3, Performance.performances
      assert_equal 1, AcidicJob::Execution.count

      execution = AcidicJob::Execution.first

      assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
      assert_equal "FINISHED", execution.recover_to

      assert_equal 8, AcidicJob::Entry.count
      assert_equal(
        [%w[enqueue_jobs started],
         %w[enqueue_jobs succeeded],
         %w[await_jobs started],
         %w[await_jobs halted],
         %w[await_jobs started],
         %w[await_jobs succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      assert_equal 3, AcidicJob::Value.count
      job_ids = AcidicJob::Value.find_by(key: "job_ids").value

      job_ids.each do |job_id|
        assert AcidicJob::Value.find_by(key: job_id).value
      end
    end

    test "simulation" do
      job = Job.new
      simulation = JobCrucible::Simulation.new(job, seed: Minitest.seed, depth: 1)
      simulation.run do |scenario|
        assert_predicate scenario, :all_executed?

        execution_id, recover_to = AcidicJob::Execution.where(idempotency_key: job.idempotency_key)
                                                       .pick(:id, :recover_to)

        refute_nil execution_id, scenario.inspect
        assert_equal "FINISHED", recover_to

        logs = AcidicJob::Entry.where(execution_id: execution_id).order(timestamp: :asc).pluck(:step, :action)

        assert_equal 3, logs.count { |_, action| action == "succeeded" }, scenario.inspect
        assert_equal 4, logs.count { |_, action| action == "started" }, scenario.inspect
        step_logs = logs.each_with_object({}) { |(step, status), hash| (hash[step] ||= []) << status }

        step_logs.each_value do |actions|
          assert_equal 1, actions.count { |it| it == "succeeded" }, scenario.inspect
        end

        context = AcidicJob::Value.where(execution_id: execution_id).order(created_at: :asc).pluck(:key, :value)

        assert_equal 3, context.count, scenario.inspect

        job_ids = context.find { |key, _| key == "job_ids" }&.last

        job_ids.each do |job_id|
          assert_equal true, AcidicJob::Value.find_by(key: job_id).value, scenario.inspect
        end

        assert_operator scenario.events.size, :>=, 17, scenario.inspect

        print "."
      end
    end
  end
end
