# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"
require_relative "support/test_case"

class ApplicationJob < ActiveJob::Base
  include AcidicJob
end

class TestJobWorkflows < TestCase
  include ActiveJob::TestHelper

  def setup; end

  def test_step_with_awaits_is_run_properly
    dynamic_class = Class.new(ApplicationJob) do
      dynamic_step_job = Class.new(ApplicationJob) do
        def perform; end
      end
      Object.const_set("SuccessfulAsyncJob", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [SuccessfulAsyncJob]
        end
      end
    end
    Object.const_set("JobWithSuccessfulAwaitStep", dynamic_class)

    perform_enqueued_jobs do
      JobWithSuccessfulAwaitStep.perform_now
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithSuccessfulAwaitStep")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulAsyncJob")
    assert_equal "FINISHED", child_run.recovery_point
  end

  def test_step_with_awaits_job_that_errors_does_not_progress_run_and_does_not_store_error_object_but_does_retry
    dynamic_class = Class.new(ApplicationJob) do
      dynamic_step_job = Class.new(ApplicationJob) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("ErroringAsyncJob", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [ErroringAsyncJob]
        end
      end
    end
    Object.const_set("JobWithErroringAwaitStep", dynamic_class)

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        JobWithErroringAwaitStep.perform_now
      end
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithErroringAwaitStep")
    assert_equal "await_step", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "ErroringAsyncJob")
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
  end

  def test_step_with_nested_awaits_jobs_is_run_properly
    dynamic_class = Class.new(ApplicationJob) do
      successful_async_worker = Class.new(ApplicationJob) do
        def perform
          true
        end
      end
      Object.const_set("NestedSuccessfulJob", successful_async_worker)

      nested_awaits_job = Class.new(ApplicationJob) do
        def perform
          with_acidity providing: {} do
            step :await_nested_step, awaits: [NestedSuccessfulJob]
          end
        end
      end
      Object.const_set("NestedSuccessfulAwaitsJob", nested_awaits_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [NestedSuccessfulAwaitsJob]
        end
      end
    end
    Object.const_set("JobWithSuccessfulNestedAwaitSteps", dynamic_class)

    perform_enqueued_jobs do
      JobWithSuccessfulNestedAwaitSteps.perform_now
    end

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithSuccessfulNestedAwaitSteps")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "NestedSuccessfulAwaitsJob")
    assert_equal "FINISHED", child_run.recovery_point

    grandchild_run = AcidicJob::Run.find_by(job_class: "NestedSuccessfulJob")
    assert_equal "FINISHED", grandchild_run.recovery_point
  end

  def test_step_with_nested_awaits_jobs_that_errors_in_second_level
    dynamic_class = Class.new(ApplicationJob) do
      erroring_async_worker = Class.new(ApplicationJob) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("NestedErroringJob", erroring_async_worker)

      nested_awaits_job = Class.new(ApplicationJob) do
        def perform
          with_acidity providing: {} do
            step :await_nested_step, awaits: [NestedErroringJob]
          end
        end
      end
      Object.const_set("NestedErroringAwaitsJob", nested_awaits_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [NestedErroringAwaitsJob]
        end
      end
    end
    Object.const_set("JobWithErroringNestedAwaitSteps", dynamic_class)

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        JobWithErroringNestedAwaitSteps.new.perform
      end
    end

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithErroringNestedAwaitSteps")
    assert_equal "await_step", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "NestedErroringAwaitsJob")
    assert_equal "await_nested_step", child_run.recovery_point

    grandchild_run = AcidicJob::Run.find_by(job_class: "NestedErroringJob")
    assert_nil grandchild_run.recovery_point
  end

  def test_step_with_awaits_that_takes_args_is_run_properly
    dynamic_class = Class.new(ApplicationJob) do
      dynamic_step_job = Class.new(ApplicationJob) do
        def perform(arg); end
      end
      Object.const_set("SuccessfulArgJob", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [SuccessfulArgJob.with(123)]
        end
      end
    end
    Object.const_set("JobWithSuccessfulArgAwaitStep", dynamic_class)

    perform_enqueued_jobs do
      JobWithSuccessfulArgAwaitStep.perform_now
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithSuccessfulArgAwaitStep")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulArgJob")
    assert_equal "FINISHED", child_run.recovery_point
  end

  def test_step_with_dynamic_awaits_as_symbol_is_run_properly
    dynamic_class = Class.new(ApplicationJob) do
      successful_step_job = Class.new(ApplicationJob) do
        def perform(arg); end
      end
      Object.const_set("SuccessfulDynamicAwaitFromSymbolJob", successful_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        [SuccessfulDynamicAwaitFromSymbolJob.with(123)]
      end
    end
    Object.const_set("JobWithSuccessfulDynamicAwaitsAsSymbol", dynamic_class)

    perform_enqueued_jobs do
      JobWithSuccessfulDynamicAwaitsAsSymbol.perform_now
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithSuccessfulDynamicAwaitsAsSymbol")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulDynamicAwaitFromSymbolJob")
    assert_equal "FINISHED", child_run.recovery_point
  end

  def test_step_with_dynamic_awaits_as_symbol_that_errors
    dynamic_class = Class.new(ApplicationJob) do
      erroring_step_job = Class.new(ApplicationJob) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("ErroringDynamicAwaitFromSymbolJob", erroring_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        [ErroringDynamicAwaitFromSymbolJob]
      end
    end
    Object.const_set("JobWithErroringDynamicAwaitsAsSymbol", dynamic_class)

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        JobWithErroringDynamicAwaitsAsSymbol.perform_now
      end
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithErroringDynamicAwaitsAsSymbol")
    assert_equal "await_step", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "ErroringDynamicAwaitFromSymbolJob")
    assert_nil child_run.recovery_point
  end

  def test_step_with_dynamic_awaits_as_string_is_run_properly
    dynamic_class = Class.new(ApplicationJob) do
      successful_step_job = Class.new(ApplicationJob) do
        def perform(arg); end
      end
      Object.const_set("SuccessfulDynamicAwaitFromStringJob", successful_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        [SuccessfulDynamicAwaitFromStringJob.with(123)]
      end
    end
    Object.const_set("JobWithSuccessfulDynamicAwaitsAsString", dynamic_class)

    perform_enqueued_jobs do
      JobWithSuccessfulDynamicAwaitsAsString.perform_now
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithSuccessfulDynamicAwaitsAsString")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulDynamicAwaitFromStringJob")
    assert_equal "FINISHED", child_run.recovery_point
  end

  def test_step_with_dynamic_awaits_as_string_that_errors
    dynamic_class = Class.new(ApplicationJob) do
      erroring_step_job = Class.new(ApplicationJob) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("ErroringDynamicAwaitFromStringJob", erroring_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        [ErroringDynamicAwaitFromStringJob]
      end
    end
    Object.const_set("JobWithErroringDynamicAwaitsAsString", dynamic_class)

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        JobWithErroringDynamicAwaitsAsString.perform_now
      end
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithErroringDynamicAwaitsAsString")
    assert_equal "await_step", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "ErroringDynamicAwaitFromStringJob")
    assert_nil child_run.recovery_point
  end

  def test_step_with_awaits_followed_by_another_step_is_run_properly
    dynamic_class = Class.new(ApplicationJob) do
      dynamic_step_job = Class.new(ApplicationJob) do
        def perform; end
      end
      Object.const_set("SimpleAwaitedJob", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [SimpleAwaitedJob]
          step :do_something
        end
      end

      def do_something; end
    end
    Object.const_set("JobWithAwaitStepFollowedByAnotherStep", dynamic_class)

    perform_enqueued_jobs do
      JobWithAwaitStepFollowedByAnotherStep.perform_now
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithAwaitStepFollowedByAnotherStep")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SimpleAwaitedJob")
    assert_equal "FINISHED", child_run.recovery_point
  end

  def test_step_with_awaits_that_takes_args_followed_by_another_step_is_run_properly
    dynamic_class = Class.new(ApplicationJob) do
      dynamic_step_job = Class.new(ApplicationJob) do
        def perform(arg); end
      end
      Object.const_set("SimpleAwaitedArgJob", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [SimpleAwaitedArgJob.with("hello")]
          step :do_something
        end
      end

      def do_something; end
    end
    Object.const_set("ArgJobWithAwaitStepFollowedByAnotherStep", dynamic_class)

    perform_enqueued_jobs do
      ArgJobWithAwaitStepFollowedByAnotherStep.perform_now
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "ArgJobWithAwaitStepFollowedByAnotherStep")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SimpleAwaitedArgJob")
    assert_equal "FINISHED", child_run.recovery_point
  end

  def test_step_with_nested_awaits_that_takes_args_jobs_is_run_properly
    dynamic_class = Class.new(ApplicationJob) do
      successful_async_worker = Class.new(ApplicationJob) do
        def perform(_arg)
          true
        end
      end
      Object.const_set("NestedSuccessfulArgJob", successful_async_worker)

      nested_awaits_job = Class.new(ApplicationJob) do
        def perform(_arg)
          with_acidity providing: {} do
            step :await_nested_step, awaits: [NestedSuccessfulArgJob.with("arg")]
          end
        end
      end
      Object.const_set("NestedSuccessfulAwaitsArgJob", nested_awaits_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [NestedSuccessfulAwaitsArgJob.with("arg")]
        end
      end
    end
    Object.const_set("JobWithSuccessfulNestedAwaitArgSteps", dynamic_class)

    perform_enqueued_jobs do
      JobWithSuccessfulNestedAwaitArgSteps.perform_now
    end

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithSuccessfulNestedAwaitArgSteps")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "NestedSuccessfulAwaitsArgJob")
    assert_equal "FINISHED", child_run.recovery_point

    grandchild_run = AcidicJob::Run.find_by(job_class: "NestedSuccessfulArgJob")
    assert_equal "FINISHED", grandchild_run.recovery_point
  end
end
