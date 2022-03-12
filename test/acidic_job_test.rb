# frozen_string_literal: true

require "test_helper"
require_relative "support/ride_create_job"
require "acidic_job/test_case"

class TestAcidicJobs < AcidicJob::TestCase
  include ActiveJob::TestHelper

  def setup
    @valid_params = {
      "origin_lat" => 0.0,
      "origin_lon" => 0.0,
      "target_lat" => 0.0,
      "target_lon" => 0.0
    }.freeze
    @valid_user = User.find_or_create_by(email: "user@example.com", stripe_customer_id: "tok_visa")
    @invalid_user = User.find_or_create_by(email: "user-bad-source@example.com", stripe_customer_id: "tok_chargeCustomerFail")
    @staged_job_params = { amount: 20_00, currency: "usd", user: @valid_user }
  end

  def before_setup
    super
    DatabaseCleaner.start
  end

  def after_teardown
    DatabaseCleaner.clean
    super
  end

  def create_run(params = {})
    AcidicJob::Run.create!({
      idempotency_key: "XXXX_IDEMPOTENCY_KEY",
      staged: false,
      locked_at: nil,
      last_run_at: Time.current,
      recovery_point: :create_ride_and_audit_record,
      job_class: "RideCreateJob",
      serialized_job: {
        "job_class" => "RideCreateJob",
        "job_id" => nil,
        "provider_job_id" => nil,
        "queue_name" => "default",
        "priority" => nil,
        "arguments" => [@valid_user.id, @valid_params.merge("_aj_symbol_keys" => [])],
        "executions" => 1,
        "exception_executions" => {},
        "locale" => "en",
        "timezone" => "UTC"
      },
      workflow: {
        "create_ride_and_audit_record" => {
          "does" => :create_ride_and_audit_record,
          "awaits" => [],
          "then" => :create_stripe_charge
        },
        "create_stripe_charge" => {
          "does" => :create_stripe_charge,
          "awaits" => [],
          "then" => :send_receipt
        },
        "send_receipt" => {
          "does" => :send_receipt,
          "awaits" => [],
          "then" => "FINISHED"
        }
      }
    }.deep_merge(params))
  end

  def test_that_it_has_a_version_number
    refute_nil ::AcidicJob::VERSION
  end

  class IdempotencyKeysAndRecoveryTest < TestAcidicJobs
    def test_passes_for_a_new_key
      assert_performed_with(job: SendRideReceiptJob) do
        result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
        assert_equal true, result
      end

      assert_equal true, AcidicJob::Run.first.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_returns_a_stored_result
      key = create_run(recovery_point: :FINISHED)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_passes_for_keys_that_are_unlocked
      key = create_run(locked_at: nil)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_performed_with(job: SendRideReceiptJob) do
          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal true, result
        end
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_passes_for_keys_with_a_stale_locked_at
      key = create_run(locked_at: Time.now - 1.hour - 1)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_performed_with(job: SendRideReceiptJob) do
          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal true, result
        end
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_stores_results_for_a_permanent_failure
      RideCreateJob.define_method(:error_in_create_stripe_charge, -> { true })
      key = create_run

      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises RideCreateJob::SimulatedTestingFailure do
          RideCreateJob.perform_now(@valid_user.id, @valid_params)
        end
      end
      RideCreateJob.undef_method(:error_in_create_stripe_charge)

      assert_equal "RideCreateJob::SimulatedTestingFailure", key.error_object.class.name
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_idempotency_key_method_returns_job_id
      key = create_run
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        job = RideCreateJob.new
        idempotency_key = job.idempotency_key

        assert_equal idempotency_key, job.job_id
      end
    end

    def test_idempotency_key_method_returns_job_id_memoized
      key = create_run
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        job = RideCreateJob.new
        idempotency_key = job.idempotency_key

        assert_equal idempotency_key, job.idempotency_key
      end
    end
  end

  class AtomicPhasesAndRecoveryPointsTest < TestAcidicJobs
    def test_continues_from_recovery_point_create_ride_and_audit_record
      key = create_run(recovery_point: :create_ride_and_audit_record)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_performed_with(job: SendRideReceiptJob) do
          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal true, result
        end
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
      assert_equal key.attr_accessors,
                   { "user_id" => @valid_user.id, "params" => @valid_params, "ride" => Ride.first }
    end

    def test_continues_from_recovery_point_create_stripe_charge
      ride = Ride.create(@valid_params.merge(
                           user: @valid_user
                         ))
      key = create_run(recovery_point: :create_stripe_charge, attr_accessors: { ride: ride })
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_performed_with(job: SendRideReceiptJob) do
          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal true, result
        end
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
      assert_equal key.attr_accessors,
                   { "user_id" => @valid_user.id, "params" => @valid_params, "ride" => Ride.first }
    end

    def test_continues_from_recovery_point_send_receipt
      key = create_run(recovery_point: :send_receipt)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_performed_with(job: SendRideReceiptJob) do
          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal true, result
        end
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
      assert_equal key.attr_accessors,
                   { "user_id" => @valid_user.id, "params" => @valid_params, "ride" => nil }
    end

    def test_halts_execution_of_steps_when_safely_finish_acidic_job_returned
      key = create_run(recovery_point: :send_receipt)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_performed_with(job: SendRideReceiptJob) do
          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal true, result
        end
      end
      key.reload

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
      assert_equal key.attr_accessors,
                   { "user_id" => @valid_user.id, "params" => @valid_params, "ride" => nil }
    end
  end

  class FailuresTest < TestAcidicJobs
    def test_denies_requests_where_parameters_dont_match_on_an_existing_key
      key = create_run

      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::MismatchedIdempotencyKeyAndJobArguments do
          RideCreateJob.perform_now(@valid_user.id, @valid_params.merge("origin_lat" => 10.0))
        end
      end
    end

    def test_denies_requests_that_have_an_equivalent_in_flight
      key = create_run(locked_at: Time.now)

      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::LockedIdempotencyKey do
          RideCreateJob.perform_now(@valid_user.id, @valid_params)
        end
      end
    end

    def test_unlocks_a_key_on_a_serialization_failure
      key = create_run
      raises_exception = ->(_params, _args) { raise ActiveRecord::SerializationFailure, "Serialization failure." }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Run.stub(:find_by, ->(*) { key }) do
          assert_raises ActiveRecord::SerializationFailure do
            RideCreateJob.perform_now(@valid_user.id, @valid_params)
          end
        end
      end

      key.reload
      assert_nil key.locked_at
      assert_equal "ActiveRecord::SerializationFailure", key.error_object.class.name
    end

    def test_unlocks_a_key_on_an_internal_error
      key = create_run
      raises_exception = ->(_params, _args) { raise "Internal server error!" }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Run.stub(:find_by, ->(*) { key }) do
          assert_raises StandardError do
            RideCreateJob.perform_now(@valid_user.id, @valid_params)
          end
        end
      end

      key.reload
      assert_nil key.locked_at
      assert_equal false, key.succeeded?
    end

    def test_throws_error_if_recovering_without_ride_record
      key = create_run(recovery_point: :create_stripe_charge)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises NoMethodError do
          RideCreateJob.perform_now(@valid_user.id, @valid_params)
        end
      end
      key.reload
      assert_nil key.locked_at
      assert_equal false, key.succeeded?
      assert_equal "NoMethodError", key.error_object.class.name
    end

    def test_throws_error_with_unknown_recovery_point
      key = create_run(recovery_point: :SOME_UNKNOWN_POINT)

      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::UnknownRecoveryPoint do
          RideCreateJob.perform_now(@valid_user.id, @valid_params)
        end
      end
      key.reload
      assert !key.locked_at.nil?
      assert_equal false, key.succeeded?
    end

    def test_swallows_error_when_trying_to_unlock_key_after_error
      key = create_run
      def key.update_columns(**kwargs)
        raise StandardError unless kwargs.key?(:attr_accessors)

        super
      end
      raises_exception = ->(_params, _args) { raise "Internal server error!" }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Run.stub(:find_by, ->(*) { key }) do
          assert_raises StandardError do
            RideCreateJob.perform_now(@valid_user.id, @valid_params)
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
      result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal true, result
    end

    def test_successfully_performs_synchronous_job_with_duplicate_idempotency_key
      RideCreateJob.perform_now(@valid_user.id, @valid_params)

      assert_equal 1, AcidicJob::Run.unstaged.count
      result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
      assert_equal 2, AcidicJob::Run.unstaged.count
      assert_equal true, result
    end

    def test_throws_appropriate_error_when_job_method_throws_exception
      RideCreateJob.define_method(:error_in_create_stripe_charge, -> { true })
      key = create_run
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises RideCreateJob::SimulatedTestingFailure do
          RideCreateJob.perform_now(@valid_user.id, @valid_params)
        end
      end
      RideCreateJob.undef_method(:error_in_create_stripe_charge)

      assert_equal "RideCreateJob::SimulatedTestingFailure", key.error_object.class.name
    end

    def test_successfully_handles_stripe_card_error
      assert_no_enqueued_jobs only: SendRideReceiptJob do
        result = RideCreateJob.perform_now(@invalid_user, @valid_params)
        assert_equal true, result
      end

      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal true, AcidicJob::Run.first.succeeded?
    end
  end
end
