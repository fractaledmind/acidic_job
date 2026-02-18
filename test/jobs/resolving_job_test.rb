# frozen_string_literal: true

require "test_helper"

class ResolvingJobTest < ActiveJob::TestCase
  test "context step stores primary method result when truthy" do
    ResolvingJob.perform_later(resolve_on_first_try: true)
    perform_all_jobs

    assert_equal 1, performed_jobs.size
    assert_equal 0, enqueued_jobs.size
    assert_equal 1, ChaoticJob.journal_size

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    assert_equal 4, AcidicJob::Entry.count
    assert_equal(
      [
        %w[resolve_data started],
        %w[resolve_data succeeded],
        %w[do_something started],
        %w[do_something succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # context stores the resolved data under the step name
    assert_equal({ name: "resolved" }, AcidicJob::Value.find_by(key: "resolve_data").value)
  end

  test "context step calls fallback when primary returns nil" do
    ResolvingJob.perform_later(resolve_on_first_try: false)
    perform_all_jobs

    assert_equal 1, performed_jobs.size
    assert_equal 0, enqueued_jobs.size
    assert_equal 1, ChaoticJob.journal_size

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    assert_equal 4, AcidicJob::Entry.count
    assert_equal(
      [
        %w[resolve_data started],
        %w[resolve_data succeeded],
        %w[do_something started],
        %w[do_something succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # context stores the fallback data under the step name
    assert_equal({ name: "fetched" }, AcidicJob::Value.find_by(key: "resolve_data").value)
  end

  test "context step with job fallback enqueues jobs and halts workflow" do
    class ResolvingWithJobFallbackJob < ApplicationJob
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.context :resolve_data, fallback: :fetch_data_async
          w.step :do_something
        end
      end

      def resolve_data
        nil
      end

      def fetch_data_async
        [AwaitedJob.new(execution)]
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
      end
    end

    # Use perform_now to run just the parent job (without processing enqueued children)
    ResolvingWithJobFallbackJob.perform_now

    # The workflow halted, execution is not finished
    assert_equal 1, AcidicJob::Execution.count
    execution = AcidicJob::Execution.first
    assert_equal "resolve_data", execution.recover_to
    refute execution.finished?

    # Step was started then halted
    assert_equal(
      [
        %w[resolve_data started],
        %w[resolve_data halted]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # The AwaitedJob was enqueued
    assert_equal 1, enqueued_jobs.count { |job| job["job_class"] == "AwaitedJob" }

    # do_something was never reached
    assert_equal 0, ChaoticJob.journal_size
  end

  test "context step with single job fallback enqueues and halts" do
    class ResolvingWithSingleJobFallbackJob < ApplicationJob
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.context :resolve_data, fallback: :fetch_data_async
          w.step :do_something
        end
      end

      def resolve_data
        nil
      end

      def fetch_data_async
        AwaitedJob.new(execution)
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
      end
    end

    ResolvingWithSingleJobFallbackJob.perform_now

    # The workflow halted
    execution = AcidicJob::Execution.first
    assert_equal "resolve_data", execution.recover_to
    refute execution.finished?

    # The AwaitedJob was enqueued
    assert_equal 1, enqueued_jobs.count { |job| job["job_class"] == "AwaitedJob" }
  end

  test "context step raises UndefinedMethodError for missing fallback" do
    class MissingFallbackJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.context :resolve_data, fallback: :nonexistent_method
        end
      end

      def resolve_data
        nil
      end
    end

    error = assert_raises(AcidicJob::UndefinedMethodError) do
      MissingFallbackJob.perform_now
    end
    assert_match(/nonexistent_method/, error.message)
  end
end
