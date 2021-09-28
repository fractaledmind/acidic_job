# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require_relative "support/setup"
require_relative "support/ride_create_worker"

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
class TestAcidicWorkers < Minitest::Test
  include ActiveJob::TestHelper

  def setup
    @valid_params = {
      "origin_lat" => 0.0,
      "origin_lon" => 0.0,
      "target_lat" => 0.0,
      "target_lon" => 0.0
    }.freeze
    @valid_user = User.find_by(stripe_customer_id: "tok_visa")
    @invalid_user = User.find_by(stripe_customer_id: "tok_chargeCustomerFail")
    @staged_job_params = [{ amount: 20_00, currency: "usd", user_id: @valid_user.id }.stringify_keys]
    @sidekiq_queue = Sidekiq::Queues["default"]
    RideCreateWorker.undef_method(:raise_error) if RideCreateWorker.respond_to?(:raise_error)
  end

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

  def create_key(params = {})
    AcidicJob::Key.create!({
      idempotency_key: "XXXX_IDEMPOTENCY_KEY",
      locked_at: nil,
      last_run_at: Time.current,
      recovery_point: :create_ride_and_audit_record,
      job_name: "RideCreateWorker",
      job_args: [@valid_user, @valid_params]
    }.deep_merge(params))
  end

  def test_that_it_has_a_version_number
    refute_nil ::AcidicJob::VERSION
  end

  def assert_enqueued_with(worker:, args:)
    assert_equal 1, @sidekiq_queue.size
    assert_equal worker.to_s, @sidekiq_queue.first["class"]
    assert_equal args, @sidekiq_queue.first["args"]
    @sidekiq_queue.clear
  end

  class IdempotencyKeysAndRecoveryTest < TestAcidicWorkers
    def test_passes_for_a_new_key
      result = RideCreateWorker.new.perform(@valid_user, @valid_params)
      assert_equal true, result

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, AcidicJob::Key.first.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Staged.count
    end

    def test_returns_a_stored_result
      key = create_key(recovery_point: :FINISHED)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Staged.count
    end

    def test_passes_for_keys_that_are_unlocked
      key = create_key(locked_at: nil)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Staged.count
    end

    def test_passes_for_keys_with_a_stale_locked_at
      key = create_key(locked_at: Time.now - 1.hour - 1)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Staged.count
    end

    def test_stores_results_for_a_permanent_failure
      RideCreateWorker.attr_reader(:raise_error)
      key = create_key
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises RideCreateWorker::SimulatedTestingFailure do
          RideCreateWorker.new.perform(@valid_user, @valid_params)
        end
      end
      RideCreateWorker.undef_method(:raise_error)

      assert_equal "RideCreateWorker::SimulatedTestingFailure", key.error_object.class.name
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Staged.count
    end
  end

  class AtomicPhasesAndRecoveryPointsTest < TestAcidicWorkers
    def test_continues_from_recovery_point_create_ride_and_audit_record
      key = create_key(recovery_point: :create_ride_and_audit_record)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Staged.count
    end

    def test_continues_from_recovery_point_create_stripe_charge
      key = create_key(recovery_point: :create_stripe_charge)
      Ride.create(@valid_params.merge(
                    user: @valid_user
                  ))
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Staged.count
    end

    def test_continues_from_recovery_point_send_receipt
      key = create_key(recovery_point: :send_receipt)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Staged.count
    end
  end

  class FailuresTest < TestAcidicWorkers
    def test_denies_requests_where_parameters_dont_match_on_an_existing_key
      key = create_key

      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::MismatchedIdempotencyKeyAndJobArguments do
          RideCreateWorker.new.perform(@valid_user, @valid_params.merge("origin_lat" => 10.0))
        end
      end
    end

    def test_denies_requests_that_have_an_equivalent_in_flight
      key = create_key(locked_at: Time.now)

      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::LockedIdempotencyKey do
          RideCreateWorker.new.perform(@valid_user, @valid_params)
        end
      end
    end

    def test_unlocks_a_key_on_a_serialization_failure
      key = create_key
      raises_exception = ->(_params, _args) { raise ActiveRecord::SerializationFailure, "Serialization failure." }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Key.stub(:find_by, ->(*) { key }) do
          assert_raises ActiveRecord::SerializationFailure do
            RideCreateWorker.new.perform(@valid_user, @valid_params)
          end
        end
      end

      key.reload
      assert_nil key.locked_at
      assert_equal "ActiveRecord::SerializationFailure", key.error_object.class.name
    end

    def test_unlocks_a_key_on_an_internal_error
      key = create_key
      raises_exception = ->(_params, _args) { raise "Internal server error!" }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Key.stub(:find_by, ->(*) { key }) do
          assert_raises StandardError do
            RideCreateWorker.new.perform(@valid_user, @valid_params)
          end
        end
      end

      key.reload
      assert_nil key.locked_at
      assert_equal false, key.succeeded?
    end

    def test_throws_error_if_recovering_without_ride_record
      key = create_key(recovery_point: :create_stripe_charge)

      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises ActiveRecord::RecordNotFound do
          RideCreateWorker.new.perform(@valid_user, @valid_params)
        end
      end
      key.reload
      assert_nil key.locked_at
      assert_equal false, key.succeeded?
      assert_equal "ActiveRecord::RecordNotFound", key.error_object.class.name
    end

    def test_throws_error_with_unknown_recovery_point
      key = create_key(recovery_point: :SOME_UNKNOWN_POINT)

      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::UnknownRecoveryPoint do
          RideCreateWorker.new.perform(@valid_user, @valid_params)
        end
      end
      key.reload
      assert !key.locked_at.nil?
      assert_equal false, key.succeeded?
    end

    def test_swallows_error_when_trying_to_unlock_key_after_error
      key = create_key
      def key.update_columns(**_kwargs)
        raise StandardError
      end
      raises_exception = ->(_params, _args) { raise "Internal server error!" }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Key.stub(:find_by, ->(*) { key }) do
          assert_raises StandardError do
            RideCreateWorker.new.perform(@valid_user, @valid_params)
          end
        end
      end
      key.reload
      assert !key.locked_at.nil?
      assert_equal false, key.succeeded?
    end
  end

  class SpecificTest < TestAcidicWorkers
    def test_successfully_performs_synchronous_job_with_unique_idempotency_key
      result = RideCreateWorker.new.perform(@valid_user, @valid_params)
      assert_equal 1, AcidicJob::Key.count
      assert_equal true, result
    end

    def test_successfully_performs_synchronous_job_with_duplicate_idempotency_key
      RideCreateWorker.new.perform(@valid_user, @valid_params)

      assert_equal 1, AcidicJob::Key.count
      result = RideCreateWorker.new.perform(@valid_user, @valid_params)
      assert_equal 2, AcidicJob::Key.count
      assert_equal true, result
    end

    def test_throws_appropriate_error_when_job_method_throws_exception
      RideCreateWorker.attr_reader(:raise_error)
      key = create_key
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises RideCreateWorker::SimulatedTestingFailure do
          RideCreateWorker.new.perform(@valid_user, @valid_params)
        end
      end
      RideCreateWorker.undef_method(:raise_error)

      assert_equal "RideCreateWorker::SimulatedTestingFailure", key.error_object.class.name
    end

    def test_successfully_handles_stripe_card_error
      result = RideCreateWorker.new.perform(@invalid_user, @valid_params)
      assert_equal 1, AcidicJob::Key.count
      assert_equal true, result
      assert_equal true, AcidicJob::Key.first.succeeded?
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
