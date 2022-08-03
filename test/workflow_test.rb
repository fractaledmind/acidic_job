# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"
require_relative "support/sidekiq_testing"
require_relative "support/test_case"

class CustomErrorForTesting < StandardError; end

class ApplicationWorker
  include Sidekiq::Worker
  include AcidicJob
end

class ApplicationJob < ActiveJob::Base
  include AcidicJob
end

class TestWorkflows < TestCase
  include ActiveJob::TestHelper

  def setup
    @sidekiq_queue = Sidekiq::Queues["default"]
  end

  def test_step_with_awaits_is_run_properly
    dynamic_class = Class.new(ApplicationWorker) do
      dynamic_step_job = Class.new(ApplicationWorker) do
        def perform; end
      end
      Object.const_set("SuccessfulAsyncWorker", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [SuccessfulAsyncWorker]
        end
      end
    end
    Object.const_set("WorkerWithSuccessfulAwaitStep", dynamic_class)

    WorkerWithSuccessfulAwaitStep.new.perform
    Sidekiq::Worker.drain_all

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithSuccessfulAwaitStep")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulAsyncWorker")
    assert_equal "FINISHED", child_run.recovery_point

    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_awaits_is_run_properly_active_job
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

    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_awaits_job_that_errors_does_not_progress_run_and_does_not_store_error_object_but_does_retry
    dynamic_class = Class.new(ApplicationWorker) do
      dynamic_step_job = Class.new(ApplicationWorker) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("ErroringAsyncWorker", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [ErroringAsyncWorker]
        end
      end
    end
    Object.const_set("WorkerWithErroringAwaitStep", dynamic_class)

    WorkerWithErroringAwaitStep.new.perform

    assert_raises Sidekiq::JobRetry::Handled do
      Sidekiq::Worker.drain_all
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithErroringAwaitStep")
    assert_equal "await_step", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "ErroringAsyncWorker")
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object

    retry_set = Sidekiq::RetrySet.new
    assert_equal 1, retry_set.size
    assert_equal ["ErroringAsyncWorker"], retry_set.map { _1.item["class"] }
  end

  def test_step_with_nested_awaits_jobs_is_run_properly
    dynamic_class = Class.new(ApplicationWorker) do
      successful_async_worker = Class.new(ApplicationWorker) do
        def perform
          true
        end
      end
      Object.const_set("NestedSuccessfulWorker", successful_async_worker)

      nested_awaits_job = Class.new(ApplicationWorker) do
        def perform
          with_acidity providing: {} do
            step :await_nested_step, awaits: [NestedSuccessfulWorker]
          end
        end
      end
      Object.const_set("NestedSuccessfulAwaitsWorker", nested_awaits_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [NestedSuccessfulAwaitsWorker]
        end
      end
    end
    Object.const_set("WorkerWithSuccessfulNestedAwaitSteps", dynamic_class)

    WorkerWithSuccessfulNestedAwaitSteps.new.perform
    Sidekiq::Worker.drain_all

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithSuccessfulNestedAwaitSteps")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "NestedSuccessfulAwaitsWorker")
    assert_equal "FINISHED", child_run.recovery_point

    grandchild_run = AcidicJob::Run.find_by(job_class: "NestedSuccessfulWorker")
    assert_equal "FINISHED", grandchild_run.recovery_point

    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_nested_awaits_jobs_that_errors_in_second_level
    dynamic_class = Class.new(ApplicationWorker) do
      erroring_async_worker = Class.new(ApplicationWorker) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("NestedErroringWorker", erroring_async_worker)

      nested_awaits_job = Class.new(ApplicationWorker) do
        def perform
          with_acidity providing: {} do
            step :await_nested_step, awaits: [NestedErroringWorker]
          end
        end
      end
      Object.const_set("NestedErroringAwaitsWorker", nested_awaits_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [NestedErroringAwaitsWorker]
        end
      end
    end
    Object.const_set("WorkerWithErroringNestedAwaitSteps", dynamic_class)

    WorkerWithErroringNestedAwaitSteps.new.perform

    assert_raises Sidekiq::JobRetry::Handled do
      Sidekiq::Worker.drain_all
    end

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithErroringNestedAwaitSteps")
    assert_equal "await_step", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "NestedErroringAwaitsWorker")
    assert_equal "await_nested_step", child_run.recovery_point

    grandchild_run = AcidicJob::Run.find_by(job_class: "NestedErroringWorker")
    assert_nil grandchild_run.recovery_point

    retry_set = Sidekiq::RetrySet.new
    assert_equal 1, retry_set.size
    assert_equal ["NestedErroringWorker"], retry_set.map { _1.item["class"] }
  end

  def test_step_with_awaits_that_takes_args_is_run_properly
    dynamic_class = Class.new(ApplicationWorker) do
      dynamic_step_job = Class.new(ApplicationWorker) do
        def perform(arg); end
      end
      Object.const_set("SuccessfulArgWorker", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [SuccessfulArgWorker.with(123)]
        end
      end
    end
    Object.const_set("WorkerWithSuccessfulArgAwaitStep", dynamic_class)

    WorkerWithSuccessfulArgAwaitStep.new.perform
    Sidekiq::Worker.drain_all

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithSuccessfulArgAwaitStep")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulArgWorker")
    assert_equal "FINISHED", child_run.recovery_point

    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_awaits_that_takes_args_is_run_properly_active_job
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
      JobWithSuccessfulArgAwaitStep.new.perform
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "JobWithSuccessfulArgAwaitStep")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulArgJob")
    assert_equal "FINISHED", child_run.recovery_point

    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_dynamic_awaits_as_symbol_is_run_properly
    dynamic_class = Class.new(ApplicationWorker) do
      successful_step_job = Class.new(ApplicationWorker) do
        def perform(arg); end
      end
      Object.const_set("SuccessfulDynamicAwaitFromSymbolWorker", successful_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        [SuccessfulDynamicAwaitFromSymbolWorker.with(123)]
      end
    end
    Object.const_set("WorkerWithSuccessfulDynamicAwaitsAsSymbol", dynamic_class)

    WorkerWithSuccessfulDynamicAwaitsAsSymbol.new.perform
    Sidekiq::Worker.drain_all

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithSuccessfulDynamicAwaitsAsSymbol")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulDynamicAwaitFromSymbolWorker")
    assert_equal "FINISHED", child_run.recovery_point

    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_dynamic_awaits_as_symbol_that_errors
    dynamic_class = Class.new(ApplicationWorker) do
      erroring_step_job = Class.new(ApplicationWorker) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("ErroringDynamicAwaitFromSymbolWorker", erroring_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        [ErroringDynamicAwaitFromSymbolWorker]
      end
    end
    Object.const_set("WorkerWithErroringDynamicAwaitsAsSymbol", dynamic_class)

    WorkerWithErroringDynamicAwaitsAsSymbol.new.perform
    assert_raises Sidekiq::JobRetry::Handled do
      Sidekiq::Worker.drain_all
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithErroringDynamicAwaitsAsSymbol")
    assert_equal "await_step", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "ErroringDynamicAwaitFromSymbolWorker")
    assert_nil child_run.recovery_point

    retry_set = Sidekiq::RetrySet.new
    assert_equal 1, retry_set.size
    assert_equal ["ErroringDynamicAwaitFromSymbolWorker"], retry_set.map { _1.item["class"] }
  end

  def test_step_with_dynamic_awaits_as_string_is_run_properly
    dynamic_class = Class.new(ApplicationWorker) do
      successful_step_job = Class.new(ApplicationWorker) do
        def perform(arg); end
      end
      Object.const_set("SuccessfulDynamicAwaitFromStringWorker", successful_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        [SuccessfulDynamicAwaitFromStringWorker.with(123)]
      end
    end
    Object.const_set("WorkerWithSuccessfulDynamicAwaitsAsString", dynamic_class)

    WorkerWithSuccessfulDynamicAwaitsAsString.new.perform
    Sidekiq::Worker.drain_all

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithSuccessfulDynamicAwaitsAsString")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SuccessfulDynamicAwaitFromStringWorker")
    assert_equal "FINISHED", child_run.recovery_point

    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_dynamic_awaits_as_string_that_errors
    dynamic_class = Class.new(ApplicationWorker) do
      erroring_step_job = Class.new(ApplicationWorker) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("ErroringDynamicAwaitFromStringWorker", erroring_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        [ErroringDynamicAwaitFromStringWorker]
      end
    end
    Object.const_set("WorkerWithErroringDynamicAwaitsAsString", dynamic_class)

    WorkerWithErroringDynamicAwaitsAsString.new.perform
    assert_raises Sidekiq::JobRetry::Handled do
      Sidekiq::Worker.drain_all
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithErroringDynamicAwaitsAsString")
    assert_equal "await_step", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "ErroringDynamicAwaitFromStringWorker")
    assert_nil child_run.recovery_point

    retry_set = Sidekiq::RetrySet.new
    assert_equal 1, retry_set.size
    assert_equal ["ErroringDynamicAwaitFromStringWorker"], retry_set.map { _1.item["class"] }
  end

  def test_step_with_awaits_followed_by_another_step_is_run_properly
    dynamic_class = Class.new(ApplicationWorker) do
      dynamic_step_job = Class.new(ApplicationWorker) do
        def perform; end
      end
      Object.const_set("SimpleAwaitedWorker", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [SimpleAwaitedWorker]
          step :do_something
        end
      end

      def do_something; end
    end
    Object.const_set("WorkerWithAwaitStepFollowedByAnotherStep", dynamic_class)

    WorkerWithAwaitStepFollowedByAnotherStep.new.perform
    Sidekiq::Worker.drain_all

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "WorkerWithAwaitStepFollowedByAnotherStep")
    assert_equal "FINISHED", parent_run.recovery_point

    child_run = AcidicJob::Run.find_by(job_class: "SimpleAwaitedWorker")
    assert_equal "FINISHED", child_run.recovery_point

    assert_equal 0, Sidekiq::RetrySet.new.size
  end
end
