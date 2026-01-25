# frozen_string_literal: true

require "test_helper"

class AcidicJob::WorkflowErrorsTest < ActiveJob::TestCase
  test "raises RedefiningWorkflowError when execute_workflow called twice" do
    class DoubleExecuteJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :step_1
        end
        execute_workflow(unique_by: job_id) do |w|
          w.step :step_1
        end
      end

      def step_1; end
    end

    error = assert_raises(AcidicJob::RedefiningWorkflowError) do
      DoubleExecuteJob.perform_now
    end
    assert_match(/can only call.*once/i, error.message)
  end

  test "raises UndefinedWorkflowBlockError when no block given" do
    class NoBlockJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id)
      end
    end

    error = assert_raises(AcidicJob::UndefinedWorkflowBlockError) do
      NoBlockJob.perform_now
    end
    assert_match(/block must be passed/i, error.message)
  end

  test "raises InvalidWorkflowBlockError when block takes no arguments" do
    class ZeroArityBlockJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) { }
      end
    end

    error = assert_raises(AcidicJob::InvalidWorkflowBlockError) do
      ZeroArityBlockJob.perform_now
    end
    assert_match(/workflow builder must be yielded/i, error.message)
  end

  test "raises MissingStepsError when no steps defined" do
    class EmptyWorkflowJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) { |w| }
      end
    end

    error = assert_raises(AcidicJob::MissingStepsError) do
      EmptyWorkflowJob.perform_now
    end
    assert_match(/must define at least one step/i, error.message)
  end

  test "raises UndefinedMethodError when step method doesn't exist" do
    class MissingMethodJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :nonexistent_step
        end
      end
    end

    error = assert_raises(AcidicJob::UndefinedMethodError) do
      MissingMethodJob.perform_now
    end
    assert_match(/undefined step method/i, error.message)
    assert_match(/nonexistent_step/, error.message)
  end

  test "raises ArgumentMismatchError when re-running with different arguments" do
    class ArgMismatchJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform(arg)
        execute_workflow(unique_by: "fixed-key") do |w|
          w.step :step_1
        end
      end

      def step_1
        raise DefaultsError
      end
    end

    # First run with arg=1, will fail on step_1 and leave execution record
    assert_raises(DefaultsError) do
      ArgMismatchJob.perform_now(1)
    end

    assert_equal 1, AcidicJob::Execution.count

    # Second run with arg=2 but same idempotency key (fixed-key)
    error = assert_raises(AcidicJob::ArgumentMismatchError) do
      ArgMismatchJob.perform_now(2)
    end
    assert_match(/arguments do not match/i, error.message)
    assert_match(/existing/, error.message)
    assert_match(/expected/, error.message)
  end

  test "raises DefinitionMismatchError when re-running with different workflow definition" do
    # Create a job class that can change its workflow definition
    class DynamicDefinitionJob < ActiveJob::Base
      include AcidicJob::Workflow

      cattr_accessor :workflow_variant, default: :original

      def perform
        execute_workflow(unique_by: "definition-test-key") do |w|
          if self.class.workflow_variant == :original
            w.step :step_1
            w.step :step_2
          else
            w.step :step_a
            w.step :step_b
            w.step :step_c
          end
        end
      end

      def step_1
        raise DefaultsError
      end

      def step_2; end
      def step_a; end
      def step_b; end
      def step_c; end
    end

    # Run with original definition, fail on step_1, creating an execution record
    DynamicDefinitionJob.workflow_variant = :original
    assert_raises(DefaultsError) do
      DynamicDefinitionJob.perform_now
    end

    assert_equal 1, AcidicJob::Execution.count
    execution = AcidicJob::Execution.first
    assert_equal "step_1", execution.recover_to

    # Now change the workflow definition and try to resume
    DynamicDefinitionJob.workflow_variant = :changed

    error = assert_raises(AcidicJob::DefinitionMismatchError) do
      DynamicDefinitionJob.perform_now
    end
    assert_match(/definition does not match/i, error.message)
    assert_match(/existing/, error.message)
    assert_match(/expected/, error.message)
  end

  test "raises UndefinedStepError when execution recover_to points to undefined step" do
    class ValidStepJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: "recover-test-key") do |w|
          w.step :step_1
        end
      end

      def step_1; end
    end

    # Create a valid execution first
    ValidStepJob.perform_now

    execution = AcidicJob::Execution.first
    assert execution.finished?

    # Manually corrupt the recover_to to point to a non-existent step
    execution.update_column(:recover_to, "nonexistent_step")

    # Now try to resume the workflow - should raise UndefinedStepError
    error = assert_raises(AcidicJob::UndefinedStepError) do
      ValidStepJob.perform_now
    end
    assert_match(/does not reference this step/i, error.message)
    assert_match(/nonexistent_step/, error.message)
  end

  test "retries on ActiveRecord::SerializationFailure and succeeds" do
    class SerializationRetryJob < ActiveJob::Base
      include AcidicJob::Workflow
      def perform
        execute_workflow(unique_by: "serialization-retry-test") do |w|
          w.step :step_1
        end
      end

      def step_1; end
    end

    # Mock the transaction to fail twice then succeed
    original_transaction = ActiveRecord::Base.method(:transaction)
    call_count = 0

    ActiveRecord::Base.stub(:transaction, ->(**args, &block) {
      call_count += 1
      if call_count <= 2
        raise ActiveRecord::SerializationFailure, "Serialization failure"
      end
      original_transaction.call(**args, &block)
    }) do
      SerializationRetryJob.perform_now
    end

    assert_equal 1, AcidicJob::Execution.count
    assert AcidicJob::Execution.first.finished?
  end

  test "raises InitializeWorkflowRetriesExhaustedError after max retries" do
    class SerializationExhaustedJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: "serialization-exhausted-test") do |w|
          w.step :step_1
        end
      end

      def step_1; end
    end

    # Mock the transaction to always fail
    ActiveRecord::Base.stub(:transaction, ->(**args, &block) {
      raise ActiveRecord::SerializationFailure, "Serialization failure"
    }) do
      error = assert_raises(AcidicJob::InitializeWorkflowRetriesExhaustedError) do
        SerializationExhaustedJob.perform_now
      end
      assert_match(/failed after.*retries/i, error.message)
    end
  end

  test "retries on ActiveRecord::Deadlocked and succeeds" do
    class DeadlockRetryJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: "deadlock-retry-test") do |w|
          w.step :step_1
        end
      end

      def step_1; end
    end

    # Mock the transaction to fail once with deadlock then succeed
    original_transaction = ActiveRecord::Base.method(:transaction)
    call_count = 0

    ActiveRecord::Base.stub(:transaction, ->(**args, &block) {
      call_count += 1
      if call_count == 1
        raise ActiveRecord::Deadlocked, "Deadlock detected"
      end
      original_transaction.call(**args, &block)
    }) do
      DeadlockRetryJob.perform_now
    end

    assert_equal 1, AcidicJob::Execution.count
    assert AcidicJob::Execution.first.finished?
  end

  test "respects configurable max retries" do
    original_max_retries = AcidicJob.initialize_workflow_max_retries

    class ConfigurableRetryJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: "configurable-retry-test") do |w|
          w.step :step_1
        end
      end

      def step_1; end
    end

    begin
      AcidicJob.initialize_workflow_max_retries = 1

      call_count = 0
      ActiveRecord::Base.stub(:transaction, ->(**args, &block) {
        call_count += 1
        raise ActiveRecord::SerializationFailure, "Serialization failure"
      }) do
        assert_raises(AcidicJob::InitializeWorkflowRetriesExhaustedError) do
          ConfigurableRetryJob.perform_now
        end
      end

      # With max_retries=1, we should have 1 initial attempt + 1 retry = 2 calls
      assert_equal 2, call_count
    ensure
      AcidicJob.initialize_workflow_max_retries = original_max_retries
    end
  end
end
