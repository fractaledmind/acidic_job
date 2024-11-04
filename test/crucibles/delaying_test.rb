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
          w.step :halt, transactional: true
          w.step :do_something
        end
      end

      def delay
        enqueue(wait: 14.days)
        @ctx[:halt] = true
      end

      def halt
        return unless @ctx[:halt]

        @ctx[:halt] = false
        halt_step!
      end

      def do_something
        Performance.performed!(serialize)
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      window = 1.minute.from_now
      flush_enqueued_jobs(at: window) until enqueued_jobs_with(at: window).empty?

      # Performed the first job, then retried it
      assert_equal 1, performed_jobs.size
      # Job in 14 days hasn't been executed yet
      assert_equal 1, enqueued_jobs.size

      # First, test the state of the execution after the first job is halted
      assert_equal 0, Performance.total
      assert_equal 1, AcidicJob::Execution.count

      execution = AcidicJob::Execution.first

      assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
      assert_equal "halt", execution.recover_to

      assert_equal 4, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt halted]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      # Now, perform the future scheduled job and check the final state of the execution
      flush_enqueued_jobs until enqueued_jobs_with.empty?

      assert_equal 1, Performance.total
      assert_equal 1, AcidicJob::Execution.count

      execution = AcidicJob::Execution.first

      assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
      assert_equal "FINISHED", execution.recover_to

      assert_equal 8, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt halted],
         %w[halt started],
         %w[halt succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      job_that_performed = Performance.all.first

      assert_in_delta Time.parse(job_that_performed["scheduled_at"]).to_i, 14.days.from_now.to_i, 1, 1
    end

    test "simulation" do
      # TODO: how to test with stubs?
      # test that my side-effects happened, and that they happened idempotently (only once)
      simulation = JobCrucible::Simulation.new(Job.new, test: self, seed: Minitest.seed, depth: 1)
      simulation.run do |scenario|
        assert_predicate scenario, :all_executed?, scenario.inspect

        execution = AcidicJob::Execution.first

        refute_nil execution.id, scenario.inspect
        assert_equal "FINISHED", execution.recover_to, scenario.inspect

        logs = AcidicJob::Entry.where(execution: execution).order(timestamp: :asc).pluck(:step, :action)

        assert_equal 3, logs.count { |_, action| action == "succeeded" }, scenario.inspect
        # if error occurs during `delay` step, can have more than 1 start for that step
        assert_operator logs.count { |_, action| action == "started" }, :>=, 3, scenario.inspect
        step_logs = logs.each_with_object({}) { |(step, status), hash| (hash[step] ||= []) << status }

        step_logs.each_value do |actions|
          assert_equal 1, actions.count { |it| it == "succeeded" }, scenario.inspect
        end

        context = AcidicJob::Value.where(execution: execution).order(created_at: :asc).pluck(:key, :value)

        assert_equal 1, context.count, scenario.inspect
        assert_equal false, AcidicJob::Value.find_by(key: "halt").value, scenario.inspect

        assert_operator scenario.events.size, :>=, 10, scenario.inspect

        print "."
      end
    end

    test "scenario with error before halt_step!" do
      glitch = ["before", "#{__FILE__}:28"]
      job = Job.new
      scenario = JobCrucible::Scenario.new(job, glitches: [glitch])
      scenario.enact! { JobCrucible::Performance.only_retries(job) }

      # Performed the first job, then retried it
      assert_equal 2, performed_jobs.size
      # Job in 14 days hasn't been executed yet
      assert_equal 1, enqueued_jobs.size

      assert_predicate scenario, :all_executed?, scenario.inspect

      assert_equal 0, Performance.total
      assert_equal 1, AcidicJob::Execution.count

      execution = AcidicJob::Execution.first

      assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
      assert_equal "halt", execution.recover_to

      assert_equal 6, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt errored],
         %w[halt started],
         %w[halt halted]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      # Now, perform the future scheduled job and check the final state of the execution
      JobCrucible::Performance.with_future(job)

      assert_equal 1, Performance.total
      assert_equal 1, AcidicJob::Execution.count

      execution = AcidicJob::Execution.first

      assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
      assert_equal "FINISHED", execution.recover_to

      assert_equal 10, AcidicJob::Entry.count
      assert_equal(
        [%w[delay started],
         %w[delay succeeded],
         %w[halt started],
         %w[halt errored],
         %w[halt started],
         %w[halt halted],
         %w[halt started],
         %w[halt succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      assert_equal 1, AcidicJob::Value.count
      assert_equal false, AcidicJob::Value.find_by(key: "halt").value

      job_that_performed = Performance.all.first

      assert_in_delta Time.parse(job_that_performed["scheduled_at"]).to_i, 14.days.from_now.to_i, 1
    end

    # test "scenario with error before setting halt intention" do
    #   Job.retry_on JobCrucible::RetryableError
    #   scenario = JobCrucible::Scenario.new
    #   scenario.before("#{__FILE__}:21") do
    #     raise JobCrucible::RetryableError
    #   end
    #   scenario.enable do
    #     Job.perform_later
    #     window = 1.minute.from_now
    #     flush_enqueued_jobs(at: window) until enqueued_jobs_with(at: window).empty?
    #   end

    #   # Performed the first job, then retried it
    #   assert_equal 2, performed_jobs.size
    #   # Job in 14 days hasn't been executed yet, but has been enqueued twice
    #   assert_equal 2, enqueued_jobs.size

    #   assert_predicate scenario, :all_executed?, scenario.inspect

    #   assert_equal 0, Performance.total
    #   assert_equal 1, AcidicJob::Execution.count

    #   execution = AcidicJob::Execution.first

    #   assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
    #   assert_equal "halt", execution.recover_to

    #   assert_equal 6, AcidicJob::Entry.count
    #   assert_equal(
    #     [%w[delay started],
    #      %w[delay errored],
    #      %w[delay started],
    #      %w[delay succeeded],
    #      %w[halt started],
    #      %w[halt halted]],
    #     execution.entries.order(timestamp: :asc).pluck(:step, :action)
    #   )

    #   assert_equal 1, AcidicJob::Value.count
    #   assert_equal false, AcidicJob::Value.find_by(key: "halt").value

    #   # Now, perform the future scheduled job and check the final state of the execution
    #   flush_enqueued_jobs until enqueued_jobs_with.empty?

    #   assert_equal 1, Performance.total
    #   assert_equal 1, AcidicJob::Execution.count

    #   execution = AcidicJob::Execution.first

    #   assert_equal [self.class.name, "Job"].join("::"), execution.serialized_job["job_class"]
    #   assert_equal "FINISHED", execution.recover_to

    #   assert_equal 10, AcidicJob::Entry.count
    #   assert_equal(
    #     [%w[delay started],
    #      %w[delay errored],
    #      %w[delay started],
    #      %w[delay succeeded],
    #      %w[halt started],
    #      %w[halt halted],
    #      %w[halt started],
    #      %w[halt succeeded],
    #      %w[do_something started],
    #      %w[do_something succeeded]],
    #     execution.entries.order(timestamp: :asc).pluck(:step, :action)
    #   )

    #   assert_equal 1, AcidicJob::Value.count
    #   assert_equal false, AcidicJob::Value.find_by(key: "halt").value

    #   job_that_performed = Performance.all.first

    #   assert_in_delta Time.parse(job_that_performed["scheduled_at"]).to_i, 14.days.from_now.to_i
    # end
  end
end
