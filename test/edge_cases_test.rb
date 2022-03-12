# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/test_case"

class CustomErrorForTesting < StandardError; end

# -----------------------------------------------------------------------------

class TestEdgeCases < AcidicJob::TestCase
  def before_setup
    super
    Sidekiq::Queues.clear_all
  end

  def after_teardown
    Sidekiq::Queues.clear_all
    super
  end

  def test_rescued_error_in_perform_does_not_prevent_error_object_from_being_stored
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform
        with_acidity do
          step :do_something
        end
      rescue CustomErrorForTesting
        true
      end

      def do_something
        raise CustomErrorForTesting
      end
    end
    Object.const_set("WorkerWithRescueInPerform", dynamic_class)

    WorkerWithRescueInPerform.new.perform

    assert_equal 1, AcidicJob::Run.count
    assert_equal CustomErrorForTesting, AcidicJob::Run.first.error_object.class
  end

  def test_error_in_first_step_rolls_back_step_transaction
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform
        with_acidity providing: { accessor: nil } do
          step :do_something
        end
      end

      def do_something
        self.accessor = "value"
        raise CustomErrorForTesting
      end
    end
    Object.const_set("WorkerWithErrorInsidePhaseTransaction", dynamic_class)

    assert_raises CustomErrorForTesting do
      WorkerWithErrorInsidePhaseTransaction.new.perform
    end

    assert_equal 1, AcidicJob::Run.count
    assert_equal CustomErrorForTesting, AcidicJob::Run.first.error_object.class
    assert_equal AcidicJob::Run.first.attr_accessors, { "accessor" => nil }
  end

  def test_logic_inside_acidic_block_is_executed_appropriately
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform(bool)
        with_acidity do
          step :do_something if bool
        end
      end

      def do_something
        raise CustomErrorForTesting
      end
    end
    Object.const_set("WorkerWithLogicInsideAcidicBlock", dynamic_class)

    assert_raises CustomErrorForTesting do
      WorkerWithLogicInsideAcidicBlock.new.perform(true)
    end

    assert_raises AcidicJob::NoDefinedSteps do
      WorkerWithLogicInsideAcidicBlock.new.perform(false)
    end

    assert_equal 1, AcidicJob::Run.count
  end

  def test_deprecated_syntax_still_works
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform
        idempotently with: {} do
          step :do_something
        end
      end

      def do_something
        raise CustomErrorForTesting
      end
    end
    Object.const_set("WorkerWithOldSyntax", dynamic_class)

    assert_raises CustomErrorForTesting do
      WorkerWithOldSyntax.new.perform
    end

    assert_equal 1, AcidicJob::Run.unstaged.count
  end

  def test_invalid_worker_raise_error
    assert_raises AcidicJob::UnknownJobAdapter do
      Class.new do
        include AcidicJob
      end
    end
  end

  def test_worker_with_no_steps_throws_error
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform
        with_acidity do
          2 * 2
        end
      end
    end
    Object.const_set("WorkerWithNoSteps", dynamic_class)

    assert_raises AcidicJob::NoDefinedSteps do
      WorkerWithNoSteps.new.perform
    end
  end

  def test_worker_return_value_in_with_acidity_block
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform
        with_acidity do
          step :do_something
          123
        end
      end
    end
    Object.const_set("WorkerWithBlockReturn", dynamic_class)

    WorkerWithBlockReturn.new.perform

    assert_equal 1, AcidicJob::Run.unstaged.count
  end

  def test_worker_identified_by_job_id_by_default
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform
        with_acidity do
          step :no_op
        end
      end
    end
    Object.const_set("WorkerIdentifiedByJIDByDefault", dynamic_class)

    job = WorkerIdentifiedByJIDByDefault.new
    job.jid = "1234567890"
    job.perform
    assert_equal "1234567890", job.idempotency_key
    assert_equal :job_id, job.instance_variable_get(:@__acidic_job_unique_by)
  end

  def test_worker_identified_by_job_id
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform
        with_acidity unique_by: :job_id do
          step :no_op
        end
      end
    end
    Object.const_set("WorkerIdentifiedByJID", dynamic_class)

    job = WorkerIdentifiedByJID.new
    job.jid = "0987654321"
    job.perform
    assert_equal "0987654321", job.idempotency_key
    assert_equal :job_id, job.instance_variable_get(:@__acidic_job_unique_by)
  end

  def test_worker_identified_by_job_args
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob

      def perform
        with_acidity unique_by: { key: :value } do
          step :no_op
        end
      end
    end
    Object.const_set("WorkerIdentifiedByArgs", dynamic_class)

    job = WorkerIdentifiedByArgs.new
    job.jid = "6574839201"
    job.perform
    assert_equal "a5223b11b410e5e48bce3ca95466de12688eb404", job.idempotency_key
    assert_equal({ key: :value }, job.instance_variable_get(:@__acidic_job_unique_by))
  end
end
