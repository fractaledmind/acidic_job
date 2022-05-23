# frozen_string_literal: true

require "test_helper"
require_relative "support/sidekiq_batches"
require_relative "support/test_case"

class CustomErrorForTesting < StandardError; end

class TestWorkflows < TestCase
  def setup
    @sidekiq_queue = Sidekiq::Queues["default"]
  end

  def test_step_with_awaits_is_run_properly
    dynamic_class = Class.new(Support::Sidekiq::Workflow) do
      include Sidekiq::Worker
      include AcidicJob

      dynamic_step_job = Class.new(Support::Sidekiq::StepWorker) do
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

    assert_equal 1, AcidicJob::Run.count
    assert_equal "FINISHED", AcidicJob::Run.first.recovery_point
    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_awaits_job_that_errors_does_not_progress_run_and_does_not_store_error_object_but_does_retry
    dynamic_class = Class.new(Support::Sidekiq::Workflow) do
      include Sidekiq::Worker
      include AcidicJob

      dynamic_step_job = Class.new(Support::Sidekiq::StepWorker) do
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

    assert_equal 1, AcidicJob::Run.count
    assert_equal "await_step", AcidicJob::Run.first.recovery_point
    assert_nil AcidicJob::Run.first.error_object
    assert_equal 1, Sidekiq::RetrySet.new.size
  end

  def test_step_with_nested_awaits_jobs_is_run_properly
    dynamic_class = Class.new(Support::Sidekiq::Workflow) do
      include Sidekiq::Worker
      include AcidicJob

      erroring_async_worker = Class.new(Support::Sidekiq::StepWorker) do
        def perform
          true
        end
      end
      Object.const_set("NestedSuccessfulWorker", erroring_async_worker)

      nested_awaits_job = Class.new(Support::Sidekiq::StepWorker) do
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

    assert_equal 2, AcidicJob::Run.count
    assert_equal "FINISHED", AcidicJob::Run.first.recovery_point
    assert_equal "FINISHED", AcidicJob::Run.second.recovery_point
    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_nested_awaits_jobs_that_errors_in_second_level
    dynamic_class = Class.new(Support::Sidekiq::Workflow) do
      include Sidekiq::Worker
      include AcidicJob

      erroring_async_worker = Class.new(Support::Sidekiq::StepWorker) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("NestedErroringWorker", erroring_async_worker)

      nested_awaits_job = Class.new(Support::Sidekiq::StepWorker) do
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

    assert_equal 2, AcidicJob::Run.count
    assert_equal "await_step", AcidicJob::Run.first.recovery_point
    assert_equal "await_nested_step", AcidicJob::Run.second.recovery_point

    retry_set = Sidekiq::RetrySet.new
    assert_equal 1, retry_set.size
    assert_equal ["NestedErroringWorker"], retry_set.map { _1.item["class"] }
  end

  def test_step_with_awaits_that_takes_args_is_run_properly
    dynamic_class = Class.new(Support::Sidekiq::Workflow) do
      include Sidekiq::Worker
      include AcidicJob

      dynamic_step_job = Class.new(Support::Sidekiq::StepWorker) do
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

    assert_equal 1, AcidicJob::Run.count
    assert_equal "FINISHED", AcidicJob::Run.first.recovery_point
    assert_equal 0, Sidekiq::RetrySet.new.size
  end

  def test_step_with_dynamic_awaits_as_symbol_is_run_properly
    dynamic_class = Class.new(Support::Sidekiq::Workflow) do
      include Sidekiq::Worker
      include AcidicJob

      successful_step_job = Class.new(Support::Sidekiq::StepWorker) do
        def perform(arg); end
      end
      Object.const_set("SuccessfulDynamicAwaitFromSymbolWorker", successful_step_job)

      erroring_step_job = Class.new(Support::Sidekiq::StepWorker) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("ErroringDynamicAwaitFromSymbolWorker", erroring_step_job)

      def perform(bool)
        @bool = bool

        with_acidity providing: {} do
          step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        return [SuccessfulDynamicAwaitFromSymbolWorker.with(123)] if @bool

        [ErroringDynamicAwaitFromSymbolWorker]
      end
    end
    Object.const_set("WorkerWithDynamicAwaitsAsSymbol", dynamic_class)

    WorkerWithDynamicAwaitsAsSymbol.new.perform(true)
    Sidekiq::Worker.drain_all

    assert_equal 1, AcidicJob::Run.count
    assert_equal "FINISHED", AcidicJob::Run.first.recovery_point
    assert_equal 0, Sidekiq::RetrySet.new.size

    WorkerWithDynamicAwaitsAsSymbol.new.perform(false)
    assert_raises Sidekiq::JobRetry::Handled do
      Sidekiq::Worker.drain_all
    end
  end

  def test_step_with_dynamic_awaits_as_string_is_run_properly
    dynamic_class = Class.new(Support::Sidekiq::Workflow) do
      include Sidekiq::Worker
      include AcidicJob

      successful_step_job = Class.new(Support::Sidekiq::StepWorker) do
        def perform(arg); end
      end
      Object.const_set("SuccessfulDynamicAwaitFromStringWorker", successful_step_job)

      erroring_step_job = Class.new(Support::Sidekiq::StepWorker) do
        def perform
          raise CustomErrorForTesting
        end
      end
      Object.const_set("ErroringDynamicAwaitFromSymbolWorker", erroring_step_job)

      def perform(bool)
        @bool = bool

        with_acidity providing: {} do
          step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        return [SuccessfulDynamicAwaitFromStringWorker.with(123)] if @bool

        [ErroringDynamicAwaitFromSymbolWorker]
      end
    end
    Object.const_set("WorkerWithDynamicAwaitsAsString", dynamic_class)

    WorkerWithDynamicAwaitsAsString.new.perform(true)
    Sidekiq::Worker.drain_all

    assert_equal 1, AcidicJob::Run.count
    assert_equal "FINISHED", AcidicJob::Run.first.recovery_point
    assert_equal 0, Sidekiq::RetrySet.new.size

    WorkerWithDynamicAwaitsAsString.new.perform(false)
    assert_raises Sidekiq::JobRetry::Handled do
      Sidekiq::Worker.drain_all
    end
  end
end
