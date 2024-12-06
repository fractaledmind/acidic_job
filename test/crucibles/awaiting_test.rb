# frozen_string_literal: true

require "test_helper"

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
          ChaoticJob.log_to_journal!
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
          ChaoticJob.log_to_journal!
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

        ctx[:job_ids] = [job_1.job_id, job_2.job_id]
        ctx[job_1.job_id] = false
        ctx[job_2.job_id] = false
      end

      def await_jobs
        ctx[:job_ids].each do |job_id|
          halt_step! unless ctx[job_id]
        end
      end

      def do_something
        ChaoticJob.log_to_journal!
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      assert_equal 3, ChaoticJob.journal_size
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
      run_simulation(Job.new) do |scenario|
        execution = AcidicJob::Execution.first

        refute_nil execution.id, scenario.inspect
        assert_equal "FINISHED", execution.recover_to

        logs = AcidicJob::Entry.where(execution: execution).order(timestamp: :asc).pluck(:step, :action)

        assert_equal 3, logs.count { |_, action| action == "succeeded" }, scenario.inspect
        # if error occurs during `enqueue_jobs` step, can have more than 1 start for that step
        assert_operator logs.count { |_, action| action == "started" }, :>=, 4, scenario.inspect
        step_logs = logs.each_with_object({}) { |(step, status), hash| (hash[step] ||= []) << status }

        step_logs.each_value do |actions|
          assert_equal 1, actions.count { |it| it == "succeeded" }, scenario.inspect
        end

        context = AcidicJob::Value.where(execution: execution).order(created_at: :asc).pluck(:key, :value)

        # If error occurs after some jobs enqueued, but before new ctx is set, can have more than 3
        assert_operator context.count, :>=, 3, [scenario.inspect, context]

        job_ids = context.find { |key, _| key == "job_ids" }&.last

        job_ids.each do |job_id|
          assert_equal true, AcidicJob::Value.find_by(key: job_id).value, scenario.inspect
        end

        assert_operator scenario.events.size, :>=, 17, scenario.inspect
      end
    end
  end
end
