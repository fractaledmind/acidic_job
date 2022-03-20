# frozen_string_literal: true

require "test_helper"
require_relative "./support/sidekiq_testing"
require_relative "./support/test_case"

class CustomErrorForTesting < StandardError; end

# -----------------------------------------------------------------------------

class TestEdgeCases < TestCase
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
        idempotently do
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

      def perform; end
    end
    Object.const_set("WorkerIdentifiedByJIDByDefault", dynamic_class)

    assert_equal :job_id, WorkerIdentifiedByJIDByDefault.instance_variable_get(:@acidic_identifier)

    job = WorkerIdentifiedByJIDByDefault.new
    job.jid = "1234567890"
    assert_equal "1234567890", job.idempotency_key
  end

  def test_worker_identified_by_job_id
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob
      acidic_by_job_id

      def perform; end
    end
    Object.const_set("WorkerIdentifiedByJID", dynamic_class)

    assert_equal :job_id, WorkerIdentifiedByJID.instance_variable_get(:@acidic_identifier)

    job = WorkerIdentifiedByJID.new
    job.jid = "0987654321"
    assert_equal "0987654321", job.idempotency_key
  end

  def test_worker_identified_by_job_args
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob
      acidic_by_job_args

      def perform; end
    end
    Object.const_set("WorkerIdentifiedByArgs", dynamic_class)

    assert_equal :job_args, WorkerIdentifiedByArgs.instance_variable_get(:@acidic_identifier)

    job = WorkerIdentifiedByArgs.new
    job.jid = "6574839201"
    assert_equal "9e59feb9d200a24f8b9f9886799be32a7d851f71", job.idempotency_key
  end

  def test_worker_identified_by_proc
    dynamic_class = Class.new do
      include Sidekiq::Worker
      include AcidicJob
      acidic_by ->(review:) { [review.id, review.aasm_state] }

      def perform(review:)
        with_acidity providing: { review: review, lifecycle_event: nil } do
          step :no_op
        end
      end
    end
    Object.const_set("WorkerIdentifiedByProc", dynamic_class)

    assert_equal Proc, WorkerIdentifiedByProc.instance_variable_get(:@acidic_identifier).class
    review_class = Struct.new(:id, :aasm_state)
    review = review_class.new(123, :initiated)

    job = WorkerIdentifiedByProc.new(review: review)
    job.jid = "6574839201"
    assert_equal "759dc9e1dc03edf16fd49f3990a3d50fbdc10bf7", job.idempotency_key
  end

  def test_job_identified_by_proc
    dynamic_class = Class.new(ActiveJob::Base) do
      include AcidicJob
      acidic_by ->(review:) { [review.id, review.aasm_state] }

      def perform(review:)
        with_acidity providing: { review: review, lifecycle_event: nil } do
          step :no_op
        end
      end
    end
    Object.const_set("JobIdentifiedByProc", dynamic_class)

    assert_equal Proc, JobIdentifiedByProc.instance_variable_get(:@acidic_identifier).class
    review_class = Struct.new(:id, :aasm_state)
    review = review_class.new(123, :initiated)

    job = JobIdentifiedByProc.new(review: review)
    job.job_id = "6574839201"
    assert_equal "759dc9e1dc03edf16fd49f3990a3d50fbdc10bf7", job.idempotency_key
  end
end
