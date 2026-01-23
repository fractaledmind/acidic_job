# frozen_string_literal: true

require "test_helper"

class AcidicJob::Plugins::TransactionalStepTest < ActiveSupport::TestCase
  # ============================================
  # Validation tests
  # ============================================

  test "validate accepts true" do
    result = AcidicJob::Plugins::TransactionalStep.validate(true)
    assert_equal true, result
  end

  test "validate accepts false" do
    result = AcidicJob::Plugins::TransactionalStep.validate(false)
    assert_equal false, result
  end

  test "validate accepts hash with on: Model" do
    result = AcidicJob::Plugins::TransactionalStep.validate(on: Thing)
    assert_equal({ on: Thing }, result)
  end

  test "validate accepts hash with on: AcidicJob::Execution" do
    result = AcidicJob::Plugins::TransactionalStep.validate(on: AcidicJob::Execution)
    assert_equal({ on: AcidicJob::Execution }, result)
  end

  test "validate rejects string" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate("invalid")
    end
    assert_match(/must be boolean or hash/, error.message)
  end

  test "validate rejects integer" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate(123)
    end
    assert_match(/must be boolean or hash/, error.message)
  end

  test "validate rejects nil" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate(nil)
    end
    assert_match(/must be boolean or hash/, error.message)
  end

  test "validate rejects array" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate([ Thing ])
    end
    assert_match(/must be boolean or hash/, error.message)
  end

  test "validate rejects hash without on key" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate(model: Thing)
    end
    assert_match(/must have `on` key/, error.message)
  end

  test "validate rejects hash with empty keys" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate({})
    end
    assert_match(/must have `on` key/, error.message)
  end

  test "validate rejects hash with on: string" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate(on: "Thing")
    end
    assert_match(/must have module value/, error.message)
  end

  test "validate rejects hash with on: symbol" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate(on: :Thing)
    end
    assert_match(/must have module value/, error.message)
  end

  test "validate rejects hash with on: nil" do
    error = assert_raises(ArgumentError) do
      AcidicJob::Plugins::TransactionalStep.validate(on: nil)
    end
    assert_match(/must have module value/, error.message)
  end

  # ============================================
  # Integration tests - transactional behavior
  # ============================================

  test "transactional: true wraps step in AcidicJob::Execution transaction" do
    class TransactionalTrueJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :create_thing, transactional: true
        end
      end

      def create_thing
        Thing.create!
        raise StandardError, "rollback"
      end
    end

    assert_raises(StandardError) do
      TransactionalTrueJob.perform_now
    end

    # Thing creation should be rolled back
    assert_equal 0, Thing.count
  end

  test "transactional: false does not wrap step in transaction" do
    class TransactionalFalseJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :create_thing, transactional: false
        end
      end

      def create_thing
        Thing.create!
        raise StandardError, "no rollback"
      end
    end

    assert_raises(StandardError) do
      TransactionalFalseJob.perform_now
    end

    # Thing creation should NOT be rolled back
    assert_equal 1, Thing.count
  end

  test "transactional: { on: Model } wraps step in that model's transaction" do
    class TransactionalOnModelJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :create_thing, transactional: { on: Thing }
        end
      end

      def create_thing
        Thing.create!
        raise StandardError, "rollback via Thing"
      end
    end

    assert_raises(StandardError) do
      TransactionalOnModelJob.perform_now
    end

    # Thing creation should be rolled back via Thing.transaction
    assert_equal 0, Thing.count
  end

  test "step without transactional option does not wrap in transaction" do
    class NonTransactionalJob < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :create_thing
        end
      end

      def create_thing
        Thing.create!
        raise StandardError, "no rollback"
      end
    end

    assert_raises(StandardError) do
      NonTransactionalJob.perform_now
    end

    # Thing creation should NOT be rolled back (no transaction wrapper)
    assert_equal 1, Thing.count
  end

  test "transactional step rolls back on retry error but persists on success" do
    class TransactionalRetryJob < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :create_thing, transactional: true
        end
      end

      def create_thing
        Thing.create!
        raise DefaultsError if executions == 1
      end
    end

    TransactionalRetryJob.perform_later
    perform_all_jobs

    # First attempt rolls back, second attempt succeeds
    # So only 1 Thing should exist (from successful second attempt)
    assert_equal 1, Thing.count
  end
end
