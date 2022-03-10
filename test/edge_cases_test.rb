# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"

class CustomErrorForTesting < StandardError; end

class WorkerWithRescueInPerform
  include Sidekiq::Worker
  include AcidicJob

  def perform
    with_acidity given: {} do
      step :do_something
    end
  rescue CustomErrorForTesting
    true
  end

  def do_something
    raise CustomErrorForTesting
  end
end

class WorkerWithErrorInsidePhaseTransaction
  include Sidekiq::Worker
  include AcidicJob

  def perform
    with_acidity given: { accessor: nil } do
      step :do_something
    end
  end

  def do_something
    self.accessor = "value"
    raise CustomErrorForTesting
  end
end

class WorkerWithLogicInsideAcidicBlock
  include Sidekiq::Worker
  include AcidicJob

  def perform(bool)
    with_acidity given: {} do
      step :do_something if bool
    end
  end

  def do_something
    raise CustomErrorForTesting
  end
end

class WorkerWithOldSyntax
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

class WorkerIdentifiedByJIDByDefault
  include Sidekiq::Worker
  include AcidicJob

  def perform; end
end

class WorkerIdentifiedByJID
  include Sidekiq::Worker
  include AcidicJob
  acidic_by_job_id

  def perform; end
end

class WorkerIdentifiedByArgs
  include Sidekiq::Worker
  include AcidicJob
  acidic_by_job_args

  def perform; end
end

class TestEdgeCases < Minitest::Test
  def before_setup
    super
    DatabaseCleaner.start
    Sidekiq::Queues.clear_all
  end

  def after_teardown
    Sidekiq::Queues.clear_all
    DatabaseCleaner.clean
    super
  end

  def test_rescued_error_in_perform_does_not_prevent_error_object_from_being_stored
    WorkerWithRescueInPerform.new.perform

    assert_equal 1, AcidicJob::Run.count
    assert_equal CustomErrorForTesting, AcidicJob::Run.first.error_object.class
  end

  def test_error_in_first_step_rolls_back_step_transaction
    assert_raises CustomErrorForTesting do
      WorkerWithErrorInsidePhaseTransaction.new.perform
    end

    assert_equal 1, AcidicJob::Run.count
    assert_equal CustomErrorForTesting, AcidicJob::Run.first.error_object.class
    assert_equal AcidicJob::Run.first.attr_accessors, { "accessor" => nil }
  end

  def test_logic_inside_acidic_block_is_executed_appropriately
    assert_raises CustomErrorForTesting do
      WorkerWithLogicInsideAcidicBlock.new.perform(true)
    end

    assert_raises AcidicJob::NoDefinedSteps do
      WorkerWithLogicInsideAcidicBlock.new.perform(false)
    end

    assert_equal 1, AcidicJob::Run.count
  end

  def test_deprecated_syntax_still_works
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

  def test_worker_identified_by_job_id_by_default
    assert_equal :job_id, WorkerIdentifiedByJIDByDefault.instance_variable_get(:@acidic_identifier)

    job = WorkerIdentifiedByJIDByDefault.new
    job.jid = "1234567890"
    assert_equal "1234567890", job.idempotency_key
  end

  def test_worker_identified_by_job_id
    assert_equal :job_id, WorkerIdentifiedByJID.instance_variable_get(:@acidic_identifier)

    job = WorkerIdentifiedByJID.new
    job.jid = "0987654321"
    assert_equal "0987654321", job.idempotency_key
  end

  def test_worker_identified_by_job_args
    assert_equal :job_args, WorkerIdentifiedByArgs.instance_variable_get(:@acidic_identifier)

    job = WorkerIdentifiedByArgs.new
    job.jid = "6574839201"
    assert_equal "9e59feb9d200a24f8b9f9886799be32a7d851f71", job.idempotency_key
  end
end
