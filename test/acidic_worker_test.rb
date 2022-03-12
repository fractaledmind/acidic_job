# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require_relative "support/ride_create_worker"
require "acidic_job/test_case"

class TestAcidicWorkers < AcidicJob::TestCase
  def setup
    @valid_params = {
      "origin_lat" => 0.0,
      "origin_lon" => 0.0,
      "target_lat" => 0.0,
      "target_lon" => 0.0
    }.freeze
    @valid_user = User.find_or_create_by(email: "user@example.com", stripe_customer_id: "tok_visa")
    @invalid_user = User.find_or_create_by(email: "user-bad-source@example.com",
                                           stripe_customer_id: "tok_chargeCustomerFail")
    @staged_job_params = [{ amount: 20_00, currency: "usd", user_id: @valid_user.id }.stringify_keys]
    @sidekiq_queue = Sidekiq::Queues["default"]
  end

  def before_setup
    super
    Sidekiq::Queues.clear_all
  end

  def after_teardown
    Sidekiq::Queues.clear_all
    super
  end

  def create_key(params = {})
    AcidicJob::Run.create!({
      idempotency_key: "XXXX_IDEMPOTENCY_KEY",
      staged: false,
      locked_at: nil,
      last_run_at: Time.current,
      recovery_point: :create_ride_and_audit_record,
      job_class: "RideCreateWorker",
      serialized_job: {
        "class" => RideCreateWorker,
        "args" => [@valid_user.id, @valid_params],
        "jid" => nil
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

  def assert_enqueued_with(worker:, args:)
    assert_equal 1, @sidekiq_queue.size
    assert_equal worker.to_s, @sidekiq_queue.first["class"]
    assert_equal args, @sidekiq_queue.first["args"]
    worker.drain
  end

  class IdempotencyKeysAndRecoveryTest < TestAcidicWorkers
    def test_passes_for_a_new_key
      result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
      assert_equal true, result

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, AcidicJob::Run.first.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_returns_a_stored_result
      key = create_key(recovery_point: :FINISHED)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
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
      key = create_key(locked_at: nil)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_passes_for_keys_with_a_stale_locked_at
      key = create_key(locked_at: Time.now - 1.hour - 1)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_stores_results_for_a_permanent_failure
      RideCreateWorker.define_method(:error_in_create_stripe_charge, -> { true })
      key = create_key
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises RideCreateWorker::SimulatedTestingFailure do
          RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        end
      end
      RideCreateWorker.undef_method(:error_in_create_stripe_charge)

      assert_equal "RideCreateWorker::SimulatedTestingFailure", key.error_object.class.name
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end
  end

  class AtomicPhasesAndRecoveryPointsTest < TestAcidicWorkers
    def test_continues_from_recovery_point_create_ride_and_audit_record
      key = create_key(recovery_point: :create_ride_and_audit_record)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 1, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_continues_from_recovery_point_create_stripe_charge
      ride = Ride.create(@valid_params.merge(
                           user: @valid_user
                         ))
      key = create_key(recovery_point: :create_stripe_charge, attr_accessors: { ride: ride })
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 1, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end

    def test_continues_from_recovery_point_send_receipt
      key = create_key(recovery_point: :send_receipt)
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        assert_equal true, result
      end
      key.reload

      assert_enqueued_with(worker: SendRideReceiptWorker, args: @staged_job_params)

      assert_equal true, key.succeeded?
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 0, Ride.count
      assert_equal 0, Audit.count
      assert_equal 0, AcidicJob::Run.staged.count
    end
  end

  class FailuresTest < TestAcidicWorkers
    def test_denies_requests_where_parameters_dont_match_on_an_existing_key
      key = create_key

      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::MismatchedIdempotencyKeyAndJobArguments do
          RideCreateWorker.new.perform(@valid_user.id, @valid_params.merge("origin_lat" => 10.0))
        end
      end
    end

    def test_denies_requests_that_have_an_equivalent_in_flight
      key = create_key(locked_at: Time.now)

      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::LockedIdempotencyKey do
          RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        end
      end
    end

    def test_unlocks_a_key_on_a_serialization_failure
      key = create_key
      raises_exception = ->(_params, _args) { raise ActiveRecord::SerializationFailure, "Serialization failure." }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Run.stub(:find_by, ->(*) { key }) do
          assert_raises ActiveRecord::SerializationFailure do
            RideCreateWorker.new.perform(@valid_user.id, @valid_params)
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
        AcidicJob::Run.stub(:find_by, ->(*) { key }) do
          assert_raises StandardError do
            RideCreateWorker.new.perform(@valid_user.id, @valid_params)
          end
        end
      end

      key.reload
      assert_nil key.locked_at
      assert_equal false, key.succeeded?
    end

    def test_throws_error_if_recovering_without_ride_record
      key = create_key(recovery_point: :create_stripe_charge)

      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises NoMethodError do
          RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        end
      end
      key.reload
      assert_nil key.locked_at
      assert_equal false, key.succeeded?
      assert_equal "NoMethodError", key.error_object.class.name
    end

    def test_throws_error_with_unknown_recovery_point
      key = create_key(recovery_point: :SOME_UNKNOWN_POINT)

      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises AcidicJob::UnknownRecoveryPoint do
          RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        end
      end
      key.reload
      assert !key.locked_at.nil?
      assert_equal false, key.succeeded?
    end

    def test_swallows_error_when_trying_to_unlock_key_after_error
      key = create_key
      def key.update_columns(**kwargs)
        raise StandardError unless kwargs.key?(:attr_accessors)

        super
      end
      raises_exception = ->(_params, _args) { raise "Internal server error!" }

      Stripe::Charge.stub(:create, raises_exception) do
        AcidicJob::Run.stub(:find_by, ->(*) { key }) do
          assert_raises StandardError do
            RideCreateWorker.new.perform(@valid_user.id, @valid_params)
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
      result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal true, result
    end

    def test_successfully_performs_synchronous_job_with_duplicate_idempotency_key
      RideCreateWorker.new.perform(@valid_user.id, @valid_params)

      assert_equal 1, AcidicJob::Run.unstaged.count
      result = RideCreateWorker.new.perform(@valid_user.id, @valid_params)
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal true, result
    end

    def test_throws_appropriate_error_when_job_method_throws_exception
      RideCreateWorker.define_method(:error_in_create_stripe_charge, -> { true })
      key = create_key
      AcidicJob::Run.stub(:find_by, ->(*) { key }) do
        assert_raises RideCreateWorker::SimulatedTestingFailure do
          RideCreateWorker.new.perform(@valid_user.id, @valid_params)
        end
      end
      RideCreateWorker.undef_method(:error_in_create_stripe_charge)

      assert_equal "RideCreateWorker::SimulatedTestingFailure", key.error_object.class.name
    end

    def test_successfully_handles_stripe_card_error
      result = RideCreateWorker.new.perform(@invalid_user, @valid_params)
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal true, result
      assert_equal true, AcidicJob::Run.first.succeeded?
    end

    def test_error_in_first_step_rolls_back_step_transaction
      RideCreateWorker.define_method(:error_in_create_ride, -> { true })

      assert_raises RideCreateWorker::SimulatedTestingFailure do
        RideCreateWorker.new.perform(@valid_user.id, @valid_params)
      end

      RideCreateWorker.undef_method(:error_in_create_ride)
      assert_equal 1, AcidicJob::Run.unstaged.count
      assert_equal 0, Ride.count
      assert_nil AcidicJob::Run.first.attr_accessors["ride"]
    end
  end
end
