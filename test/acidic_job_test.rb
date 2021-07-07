# frozen_string_literal: true

require "test_helper"
require_relative "setup"

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
class TestAcidicJobs < Minitest::Test
  include ActiveJob::TestHelper

  def setup
    @idempotency_key = "XXXX_IDEMPOTENCY_KEY"
    @valid_params = {
      "origin_lat" => 0.0,
      "origin_lon" => 0.0,
      "target_lat" => 0.0,
      "target_lon" => 0.0
    }.freeze
    @valid_user = User.find_by(stripe_customer_id: "tok_visa")
    @invalid_user = User.find_by(stripe_customer_id: "tok_chargeCustomerFail")
  end

  def before_setup
    super
    DatabaseCleaner.start
  end

  def after_teardown
    DatabaseCleaner.clean
    super
  end

  def create_key(params = {})
    AcidicJobKey.create!({
      idempotency_key: @idempotency_key,
      locked_at: nil,
      last_run_at: Time.current,
      recovery_point: :create_ride_and_audit_record,
      job_name: "RideCreateJob",
      job_args: @valid_params.as_json
    }.merge(params))
  end

  def test_that_it_has_a_version_number
    refute_nil ::AcidicJob::VERSION
  end

  class IdempotencyKeysAndRecoveryTest < TestAcidicJobs
    def test_passes_for_a_new_key
      result = RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)

      assert_equal true, result
      assert_equal true, AcidicJobKey.first.succeeded?
      assert_equal 1, AcidicJobKey.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_returns_a_stored_result
      key = create_key(recovery_point: :FINISHED)
      result = RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
      key.reload

      assert_equal true, result
      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJobKey.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, StagedJob.count
    end

    def test_passes_for_keys_that_are_unlocked
      key = create_key(locked_at: nil)
      result = RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
      key.reload

      assert_equal true, result
      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJobKey.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_passes_for_keys_with_a_stale_locked_at
      key = create_key(locked_at: Time.now - 1.hour - 1)
      result = RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
      key.reload

      assert_equal true, result
      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJobKey.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_stores_results_for_a_permanent_failure
      key = create_key

      assert_raises Stripe::CardError do
        RideCreateJob.perform_now(key.idempotency_key, @invalid_user, @valid_params)
      end
      key.reload

      assert_equal "Stripe::CardError", key.error_object.class.name
      assert_equal "Your card was declined.", key.error_object.message
      assert_equal 1, AcidicJobKey.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, StagedJob.count
    end
  end

  class AtomicPhasesAndRecoveryPointsTest < TestAcidicJobs
    def test_continues_from_recovery_point_create_ride_and_audit_record
      key = create_key(recovery_point: :create_ride_and_audit_record)
      result = RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
      key.reload

      assert_equal true, result
      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJobKey.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_continues_from_recovery_point_create_stripe_charge
      key = create_key(recovery_point: :create_stripe_charge)
      Ride.create(@valid_params.merge(
                    acidic_job_key: key,
                    user: @valid_user
                  ))
      result = RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
      key.reload

      assert_equal true, result
      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJobKey.count
      assert_equal 1, Ride.count
      assert_equal 0, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_continues_from_recovery_point_send_receipt
      key = create_key(recovery_point: :send_receipt)
      result = RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
      key.reload

      assert_equal true, result
      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJobKey.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 1, StagedJob.count
    end
  end

  class FailuresTest < TestAcidicJobs
    def test_denies_requests_that_are_missing_required_params
      assert_raises AcidicJob::MissingRequiredAttribute do
        RideCreateJob.perform_now(@idempotency_key, nil, @valid_params)
      end
    end

    def test_denies_requests_that_are_missing_a_key
      assert_raises AcidicJob::IdempotencyKeyRequired do
        RideCreateJob.perform_now(nil, @valid_user, @valid_params)
      end
    end

    def test_denies_requests_that_have_a_key_thats_too_short
      assert_raises AcidicJob::IdempotencyKeyTooShort do
        RideCreateJob.perform_now("123", @valid_user, @valid_params)
      end
    end

    def test_denies_requests_that_are_missing_parameters
      assert_raises AcidicJob::MissingRequiredAttribute do
        RideCreateJob.perform_now(@idempotency_key, @valid_user, nil)
      end
    end

    def test_denies_requests_where_parameters_dont_match_on_an_existing_key
      key = create_key

      assert_raises AcidicJob::MismatchedIdempotencyKeyAndJobArguments do
        RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params.merge("origin_lat" => 10.0))
      end
    end

    def test_denies_requests_that_have_an_equivalent_in_flight
      key = create_key(locked_at: Time.now)

      assert_raises AcidicJob::LockedIdempotencyKey do
        RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
      end
    end

    def test_unlocks_a_key_and_returns_409_on_a_serialization_failure
      key = create_key
      raises_exception = ->(_params, _args) { raise ActiveRecord::SerializationFailure, "Serialization failure." }

      Stripe::Charge.stub(:create, raises_exception) do
        assert_raises ActiveRecord::SerializationFailure do
          RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
        end
      end

      key.reload
      assert_nil key.locked_at
    end

    def test_unlocks_a_key_and_returns_500_on_an_internal_error
      key = create_key
      raises_exception = ->(_params, _args) { raise "Internal server error!" }

      Stripe::Charge.stub(:create, raises_exception) do
        assert_raises StandardError do
          RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
        end
      end

      key.reload
      assert_nil key.locked_at
    end

    def test_throws_error_if_recovering_without_ride_record
      key = create_key(recovery_point: :create_stripe_charge)

      assert_raises RideCreateJob::MissingRideAtRideCreatedRecoveryPoint do
        RideCreateJob.perform_now(key.idempotency_key, @valid_user, @valid_params)
      end
      key.reload

      assert_equal false, key.succeeded?
      assert_equal 1, AcidicJobKey.count
      assert_equal 0, Ride.count
    end
  end

  class SpecificTest < TestAcidicJobs
    def test_successfully_performs_synchronous_job_with_unique_idempotency_key
      result = RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)
      assert_equal 1, AcidicJobKey.count
      assert_equal @idempotency_key, AcidicJobKey.first.idempotency_key
      assert_equal true, result
    end

    def test_successfully_performs_synchronous_job_with_duplicate_idempotency_key
      RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)

      assert_equal 1, AcidicJobKey.count
      result = RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)
      assert_equal 1, AcidicJobKey.count
      assert_equal @idempotency_key, AcidicJobKey.first.idempotency_key
      assert_equal true, result
    end

    def test_throws_appropriate_error_with_duplicate_idempotency_keys_but_unmatched_args
      RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)

      assert_equal 1, AcidicJobKey.count
      assert_raises AcidicJob::MismatchedIdempotencyKeyAndJobArguments do
        RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params.merge("origin_lat" => 1.1))
      end
      assert_equal 1, AcidicJobKey.count
      assert_equal @idempotency_key, AcidicJobKey.first.idempotency_key
    end

    def test_throws_appropriate_error_with_duplicate_idempotency_keys_but_one_is_locked
      RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)
      AcidicJobKey.first.update(locked_at: 1.second.ago)

      assert_equal 1, AcidicJobKey.count
      assert_raises AcidicJob::LockedIdempotencyKey do
        RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)
      end
      assert_equal 1, AcidicJobKey.count
      assert_equal @idempotency_key, AcidicJobKey.first.idempotency_key
    end

    def test_throws_appropriate_error_with_duplicate_idempotency_keys_but_unknown_recovery_point
      RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)
      AcidicJobKey.first.update!(recovery_point: :INTERMEDIATE_POINT)

      assert_raises AcidicJob::UnknownRecoveryPoint do
        RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)
      end
    end

    def test_throws_appropriate_error_when_job_method_throws_exception
      RideCreateJob.attr_reader(:raise_error)
      assert_raises RideCreateJob::SimulatedTestingFailure do
        RideCreateJob.perform_now(@idempotency_key, @valid_user, @valid_params)
      end
      RideCreateJob.undef_method(:raise_error)
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
