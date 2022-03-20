# frozen_string_literal: true

require "test_helper"
require_relative "support/sidekiq_batches"
require_relative "support/test_case"

class CustomErrorForTesting < StandardError; end

class TestWorkflows < TestCase
  def setup
    @sidekiq_queue = Sidekiq::Queues["default"]
  end

  def assert_enqueued_with(worker:, args: [], size: 1)
    assert_equal size, @sidekiq_queue.size
    assert_equal worker.to_s, @sidekiq_queue.first["class"]
    assert_equal args, @sidekiq_queue.first["args"]
    @sidekiq_queue.clear
  end

  def mocking_sidekiq_batches(&block)
    Sidekiq::Batch.stub(:new, ->(*) { Support::Sidekiq::NullBatch.new }) do
      Sidekiq::Batch::Status.stub(:new, ->(*) { Support::Sidekiq::NullStatus.new }) do
        Sidekiq::Testing.fake! do
          block.call
        end
      end
    end
  end

  def test_step_with_awaits_is_run_properly
    dynamic_class = Class.new(Support::Sidekiq::Workflow) do
      include Sidekiq::Worker
      include AcidicJob

      dynamic_step_job = Class.new(Support::Sidekiq::StepWorker) do
        def perform
          call_batch_success_callback
        end
      end
      Object.const_set("SuccessfulAsyncWorker", dynamic_step_job)

      def perform
        with_acidity providing: {} do
          step :await_step, awaits: [SuccessfulAsyncWorker]
        end
      end
    end
    Object.const_set("WorkerWithSuccessfulAwaitStep", dynamic_class)

    mocking_sidekiq_batches do
      WorkerWithSuccessfulAwaitStep.new.perform
    end

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

    mocking_sidekiq_batches do
      WorkerWithErroringAwaitStep.new.perform
    end

    assert_raises Sidekiq::JobRetry::Handled do
      Sidekiq::Worker.drain_all
    end

    assert_equal 1, AcidicJob::Run.count
    assert_equal "await_step", AcidicJob::Run.first.recovery_point
    assert_nil AcidicJob::Run.first.error_object
    assert_equal 1, Sidekiq::RetrySet.new.size
  end
end
