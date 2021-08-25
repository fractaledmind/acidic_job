# frozen_string_literal: true

require "test_helper"
require_relative "setup"

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
class TestAcidicJobs < Minitest::Test
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
    RideCreateJob.undef_method(:raise_error) if RideCreateJob.respond_to?(:raise_error)
  end

  def before_setup
    super
    DatabaseCleaner.start
  end

  def after_teardown
    DatabaseCleaner.clean
    super
  end

  def serialize_job_args(user, params)
    # [{"_aj_globalid"=>"gid://test/User/1"}, {"origin_lat"=>0.0, "origin_lon"=>0.0, "target_lat"=>0.0, "target_lon"=>0.0, "_aj_symbol_keys"=>[]}]
    [{"_aj_globalid" => user.to_global_id.to_s}, params.merge("_aj_symbol_keys" => [])]
  end

  def create_key(params = {})
    AcidicJob::Key.create!({
      idempotency_key: "XXXX_IDEMPOTENCY_KEY",
      locked_at: nil,
      last_run_at: Time.current,
      recovery_point: :create_ride_and_audit_record,
      job_name: "RideCreateJob",
      job_args: serialize_job_args(@valid_user, @valid_params)
    }.deep_merge(params))
  end

  def test_that_it_has_a_version_number
    refute_nil ::AcidicJob::VERSION
  end

  class IdempotencyKeysAndRecoveryTest < TestAcidicJobs
    def test_passes_for_a_new_key
      result = RideCreateJob.perform_now(@valid_user, @valid_params)

      assert_equal true, result
      assert_equal true, AcidicJob::Key.first.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_returns_a_stored_result
      key = create_key(recovery_point: :FINISHED)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateJob.perform_now(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, StagedJob.count
    end

    def test_passes_for_keys_that_are_unlocked
      key = create_key(locked_at: nil)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateJob.perform_now(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_passes_for_keys_with_a_stale_locked_at
      key = create_key(locked_at: Time.now - 1.hour - 1)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateJob.perform_now(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_stores_results_for_a_permanent_failure
      RideCreateJob.attr_reader(:raise_error)
      key = create_key
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises RideCreateJob::SimulatedTestingFailure do
          RideCreateJob.perform_now(@valid_user, @valid_params)
        end
      end
      RideCreateJob.undef_method(:raise_error)

      assert_equal "RideCreateJob::SimulatedTestingFailure", key.error_object.class.name
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, StagedJob.count
    end
  end

  class AtomicPhasesAndRecoveryPointsTest < TestAcidicJobs
    def test_continues_from_recovery_point_create_ride_and_audit_record
      key = create_key(recovery_point: :create_ride_and_audit_record)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateJob.perform_now(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
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
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateJob.perform_now(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 1, Ride.count
      assert_equal 0, Audit.count
      assert_equal 1, StagedJob.count
    end

    def test_continues_from_recovery_point_send_receipt
      key = create_key(recovery_point: :send_receipt)
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        result = RideCreateJob.perform_now(@valid_user, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Key.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 1, StagedJob.count
    end
  end

  class FailuresTest < TestAcidicJobs
    def test_denies_requests_where_parameters_dont_match_on_an_existing_key
      key = create_key

      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::MismatchedIdempotencyKeyAndJobArguments do
          RideCreateJob.perform_now(@valid_user, @valid_params.merge("origin_lat" => 10.0))
        end
      end
    end

    def test_denies_requests_that_have_an_equivalent_in_flight
      key = create_key(locked_at: Time.now)

      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::LockedIdempotencyKey do
          RideCreateJob.perform_now(@valid_user, @valid_params)
        end
      end
    end

    def test_unlocks_a_key_on_a_serialization_failure
      key = create_key
      raises_exception = ->(_params, _args) { raise ActiveRecord::SerializationFailure, "Serialization failure." }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Key.stub(:find_by, ->(*) { key }) do
          assert_raises ActiveRecord::SerializationFailure do
            RideCreateJob.perform_now(@valid_user, @valid_params)
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
            RideCreateJob.perform_now(@valid_user, @valid_params)
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
        assert_raises RideCreateJob::MissingRideAtRideCreatedRecoveryPoint do
          RideCreateJob.perform_now(@valid_user, @valid_params)
        end
      end
      key.reload
      assert_nil key.locked_at
      assert_equal false, key.succeeded?
      assert_equal "RideCreateJob::MissingRideAtRideCreatedRecoveryPoint", key.error_object.class.name
    end

    def test_throws_error_with_unknown_recovery_point
      key = create_key(recovery_point: :SOME_UNKNOWN_POINT)

      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::UnknownRecoveryPoint do
          RideCreateJob.perform_now(@valid_user, @valid_params)
        end
      end
      key.reload
      assert !key.locked_at.nil?
      assert_equal false, key.succeeded?
    end

    def test_swallows_error_when_trying_to_unlock_key_after_error
      key = create_key
      def key.update_columns(**kwargs)
        raise StandardError
      end
      raises_exception = ->(_params, _args) { raise "Internal server error!" }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Key.stub(:find_by, ->(*) { key }) do
          assert_raises StandardError do
            RideCreateJob.perform_now(@valid_user, @valid_params)
          end
        end
      end
      key.reload
      assert !key.locked_at.nil?
      assert_equal false, key.succeeded?
    end
  end

  class SpecificTest < TestAcidicJobs
    def test_successfully_performs_synchronous_job_with_unique_idempotency_key
      result = RideCreateJob.perform_now(@valid_user, @valid_params)
      assert_equal 1, AcidicJob::Key.count
      assert_equal true, result
    end

    def test_successfully_performs_synchronous_job_with_duplicate_idempotency_key
      RideCreateJob.perform_now(@valid_user, @valid_params)

      assert_equal 1, AcidicJob::Key.count
      result = RideCreateJob.perform_now(@valid_user, @valid_params)
      assert_equal 2, AcidicJob::Key.count
      assert_equal true, result
    end

    def test_throws_appropriate_error_when_job_method_throws_exception
      RideCreateJob.attr_reader(:raise_error)
      key = create_key
      AcidicJob::Key.stub(:find_by, ->(*) { key }) do
        assert_raises RideCreateJob::SimulatedTestingFailure do
          RideCreateJob.perform_now(@valid_user, @valid_params)
        end
      end
      RideCreateJob.undef_method(:raise_error)

      assert_equal "RideCreateJob::SimulatedTestingFailure", key.error_object.class.name
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
