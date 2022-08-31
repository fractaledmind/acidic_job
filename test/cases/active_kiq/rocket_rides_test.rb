# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"
require "rocket_rides_helper"

module Cases
  module ActiveKiq
    class RocketRides < ActiveSupport::TestCase
      class SendRideReceiptJob < AcidicJob::ActiveKiq
        def perform(_context)
          Performance.performed!
        end
      end

      class RideCreateJob < AcidicJob::ActiveKiq
        class SimulatedTestingFailure < StandardError; end

        def perform(user_id, ride_params)
          @user_id = user_id
          @params = ride_params

          with_acidic_workflow persisting: { ride: nil } do |workflow|
            workflow.step :create_ride_and_audit_record
            workflow.step :create_stripe_charge
            workflow.step :send_receipt
          end
        end

        private

        def create_ride_and_audit_record
          self.ride = Ride.create!(
            origin_lat: @params["origin_lat"],
            origin_lon: @params["origin_lon"],
            target_lat: @params["target_lat"],
            target_lon: @params["target_lon"],
            stripe_charge_id: nil, # no charge created yet
            user_id: @user_id
          )

          raise SimulatedTestingFailure if self.class.instance_variable_get(:@error_in_create_ride)

          # in the same transaction insert an audit record for what happened
          Audit.create!(
            action: :AUDIT_RIDE_CREATED,
            auditable: ride,
            user_id: @user_id,
            audited_changes: @params
          )
        end

        def create_stripe_charge
          raise SimulatedTestingFailure if self.class.instance_variable_get(:@error_in_create_stripe_charge)

          begin
            user = User.find_by(id: @user_id)
            charge = Stripe::Charge.create(
              {
                amount: 20_00,
                currency: "usd",
                customer: user.stripe_customer_id,
                description: "Charge for ride #{@ride.id}"
              },
              **{
                # Pass through our own unique ID rather than the value
                # transmitted to us so that we can guarantee uniqueness to Stripe
                # across all Rocket Rides accounts.
                idempotency_key: "rocket-rides-atomic-#{idempotency_key}"
              }
            )
          rescue Stripe::CardError
            # Short circuits execution by sending execution right to 'finished'.
            # So, ends the job "successfully"
            safely_finish_acidic_job
          else
            # if there is some sort of failure here (like server downtime), what happens?
            @ride.update_column(:stripe_charge_id, charge.id)
          end
        end

        def send_receipt
          # Send a receipt asynchronously by adding an entry to the staged_jobs
          # table. By funneling the job through Postgres, we make this
          # operation transaction-safe.
          SendRideReceiptJob.perform_acidicly(
            amount: 20_00,
            currency: "usd",
            user_id: @user_id
          )
        end
      end

      def before_setup
        @valid_params = {
          "origin_lat" => 0.0,
          "origin_lon" => 0.0,
          "target_lat" => 0.0,
          "target_lon" => 0.0
        }.freeze
        @valid_user = User.find_or_create_by(email: "user@example.com", stripe_customer_id: "tok_visa")
        @invalid_user = User.find_or_create_by(email: "user-bad-source@example.com",
                                               stripe_customer_id: "tok_chargeCustomerFail")
        @staged_job_params = [{ "amount" => 20_00, "currency" => "usd", "user_id" => @valid_user.id }]
        RideCreateJob.instance_variable_set(:@error_in_create_ride, false)
        RideCreateJob.instance_variable_set(:@error_in_create_stripe_charge, false)

        super()

        AcidicJob::Run.delete_all
        Audit.delete_all
        Ride.delete_all
        Notification.delete_all
        Performance.reset!
        Sidekiq::Queues.clear_all
        Sidekiq.redis(&:flushdb)
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
            "arguments" => [@valid_user.id, @valid_params],
            "executions" => 1,
            "exception_executions" => {},
            "locale" => "en",
            "timezone" => "UTC"
          },
          workflow: {
            "create_ride_and_audit_record" => {
              "does" => "create_ride_and_audit_record",
              "awaits" => [],
              "for_each" => nil,
              "then" => "create_stripe_charge"
            },
            "create_stripe_charge" => {
              "does" => "create_stripe_charge",
              "awaits" => [],
              "for_each" => nil,
              "then" => "send_receipt"
            },
            "send_receipt" => {
              "does" => "send_receipt",
              "awaits" => [],
              "for_each" => nil,
              "then" => "FINISHED"
            }
          }
        }.deep_merge(params))
      end

      def assert_enqueued_with(job:, args: [])
        @sidekiq_queue ||= Sidekiq::Queues["default"]
        assert_equal 1, @sidekiq_queue.size
        assert_equal job.to_s, @sidekiq_queue.first["class"]
        assert_equal args, @sidekiq_queue.first["args"]
        job.drain
      end

      class IdempotencyKeysAndRecoveryTest < self
        test "passes for a new key" do
          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal true, result

          assert_enqueued_with(job: SendRideReceiptJob, args: @staged_job_params)

          run = AcidicJob::Run.find_by(job_class: [self.class.name.split("::")[0..-2], "RideCreateJob"].join("::"))
          assert_equal true, run.succeeded?
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 1, Ride.count
          assert_equal 1, Audit.count
          assert_equal 1, AcidicJob::Run.staged.count
        end

        test "returns a stored result" do
          run = create_run(recovery_point: :FINISHED)
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
            assert_equal true, result
          end
          run.reload

          assert_equal true, run.succeeded?
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 0, Ride.count
          assert_equal 0, Audit.count
          assert_equal 0, AcidicJob::Run.staged.count
          assert_equal 0, Performance.performances
        end

        test "passes for keys that are unlocked" do
          run = create_run(locked_at: nil)
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
            assert_equal true, result
          end

          assert_enqueued_with(job: SendRideReceiptJob, args: @staged_job_params)

          run.reload
          assert_equal true, run.succeeded?
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 1, Ride.count
          assert_equal 1, Audit.count
          assert_equal 1, AcidicJob::Run.staged.count
          assert_equal 1, Performance.performances
        end

        test "passes for keys with a stale locked at" do
          run = create_run(locked_at: Time.now - 1.hour - 1)
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
            assert_equal true, result
          end

          assert_enqueued_with(job: SendRideReceiptJob, args: @staged_job_params)

          run.reload
          assert_equal true, run.succeeded?
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 1, Ride.count
          assert_equal 1, Audit.count
          assert_equal 1, AcidicJob::Run.staged.count
          assert_equal 1, Performance.performances
        end

        test "stores results for a permanent failure" do
          RideCreateJob.instance_variable_set(:@error_in_create_stripe_charge, true)
          run = create_run

          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            assert_raises RideCreateJob::SimulatedTestingFailure do
              RideCreateJob.perform_now(@valid_user.id, @valid_params)
            end
          end
          RideCreateJob.instance_variable_set(:@error_in_create_stripe_charge, false)

          assert_equal [self.class.name.split("::")[0..-2], "RideCreateJob::SimulatedTestingFailure"].join("::"),
                       run.error_object.class.name
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 1, Ride.count
          assert_equal 1, Audit.count
          assert_equal 0, AcidicJob::Run.staged.count
          assert_equal 0, Performance.performances
        end

        test "`idempotency_key` method returns job_id" do
          run = create_run
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            job = RideCreateJob.new
            idempotency_key = job.idempotency_key

            assert_equal idempotency_key, job.job_id
          end
        end

        test "`idempotency_key` method returns job_id memoized" do
          run = create_run
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            job = RideCreateJob.new
            idempotency_key = job.idempotency_key

            assert_equal idempotency_key, job.idempotency_key
          end
        end
      end

      class AtomicPhasesAndRecoveryPointsTest < self
        test "continues from recovery_point `create_ride_and_audit_record`" do
          run = create_run(recovery_point: :create_ride_and_audit_record)
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
            assert_equal true, result
          end

          assert_enqueued_with(job: SendRideReceiptJob, args: @staged_job_params)

          run.reload
          assert_equal true, run.succeeded?
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 1, Ride.count
          assert_equal 1, Audit.count
          assert_equal 1, AcidicJob::Run.staged.count
          assert_equal({ "ride" => Ride.first }, run.attr_accessors)
        end

        test "continues from recovery_point `create_stripe_charge`" do
          ride = Ride.create(@valid_params.merge(
                               user: @valid_user
                             ))
          run = create_run(recovery_point: :create_stripe_charge, attr_accessors: { ride: ride })
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
            assert_equal true, result
          end

          assert_enqueued_with(job: SendRideReceiptJob, args: @staged_job_params)

          run.reload
          assert_equal true, run.succeeded?
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 1, Ride.count
          assert_equal 0, Audit.count
          assert_equal 1, AcidicJob::Run.staged.count
          assert_equal({ "ride" => Ride.first }, run.attr_accessors)
        end

        test "continues from recovery_point `send_receipt`" do
          run = create_run(recovery_point: :send_receipt)
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
            assert_equal true, result
          end

          assert_enqueued_with(job: SendRideReceiptJob, args: @staged_job_params)

          run.reload
          assert_equal true, run.succeeded?
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 0, Ride.count
          assert_equal 0, Audit.count
          assert_equal 1, AcidicJob::Run.staged.count
          assert_equal({ "ride" => nil }, run.attr_accessors)
        end

        test "halts execution of steps when `safely_finish_acidic_job` returned" do
          run = create_run(recovery_point: :send_receipt)
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
            assert_equal true, result
          end

          assert_enqueued_with(job: SendRideReceiptJob, args: @staged_job_params)

          run.reload
          assert_equal true, run.succeeded?
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal 0, Ride.count
          assert_equal 0, Audit.count
          assert_equal 1, AcidicJob::Run.staged.count
          assert_equal({ "ride" => nil }, run.attr_accessors)
        end
      end

      class FailuresTest < self
        test "denies_requests_where_parameters_dont_match_on_an_existing_run" do
          run = create_run

          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            assert_raises AcidicJob::MismatchedIdempotencyKeyAndJobArguments do
              RideCreateJob.perform_now(@valid_user.id, @valid_params.merge("origin_lat" => 10.0))
            end
          end
        end

        test "denies requests that have an equivalent running" do
          run = create_run(locked_at: Time.now)

          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            assert_raises AcidicJob::LockedIdempotencyKey do
              RideCreateJob.perform_now(@valid_user.id, @valid_params)
            end
          end
        end

        test "unlocks a run on a serialization failure" do
          run = create_run
          raises_exception = ->(_params, _args) { raise ActiveRecord::SerializationFailure, "Serialization failure." }

          Stripe::Charge.stub(:create, raises_exception) do
            AcidicJob::Run.stub(:find_by, ->(*) { run }) do
              assert_raises ActiveRecord::SerializationFailure do
                RideCreateJob.perform_now(@valid_user.id, @valid_params)
              end
            end
          end

          run.reload
          assert_nil run.locked_at
          assert_equal "ActiveRecord::SerializationFailure", run.error_object.class.name
        end

        test "unlocks a run on an internal error" do
          run = create_run
          raises_exception = ->(_params, _args) { raise "Internal server error!" }

          Stripe::Charge.stub(:create, raises_exception) do
            AcidicJob::Run.stub(:find_by, ->(*) { run }) do
              assert_raises StandardError do
                RideCreateJob.perform_now(@valid_user.id, @valid_params)
              end
            end
          end

          run.reload
          assert_nil run.locked_at
          assert_equal false, run.succeeded?
        end

        test "throws error if recovering without ride record" do
          run = create_run(recovery_point: :create_stripe_charge)
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            assert_raises NoMethodError do
              RideCreateJob.perform_now(@valid_user.id, @valid_params)
            end
          end
          run.reload
          assert_nil run.locked_at
          assert_equal false, run.succeeded?
          assert_equal "NoMethodError", run.error_object.class.name
        end

        test "throws error with unknown recovery point" do
          run = create_run(recovery_point: :SOME_UNKNOWN_POINT)

          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            assert_raises AcidicJob::UnknownRecoveryPoint do
              RideCreateJob.perform_now(@valid_user.id, @valid_params)
            end
          end
          run.reload
          assert !run.locked_at.nil?
          assert_equal false, run.succeeded?
        end

        test "swallows error when trying to unlock run after error" do
          run = create_run
          def run.store_error!(_error)
            raise RareErrorForTesting
          end
          raises_exception = ->(_params, _args) { raise CustomErrorForTesting }

          Stripe::Charge.stub(:create, raises_exception) do
            AcidicJob::Run.stub(:find_by, ->(*) { run }) do
              assert_raises CustomErrorForTesting do
                RideCreateJob.perform_now(@valid_user.id, @valid_params)
              end
            end
          end
          run.reload
          assert run.locked?
          assert_equal false, run.succeeded?
        end
      end

      class SpecificTest < self
        test "successfully performs job synchronously" do
          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal true, result
        end

        test "successfully performs job synchronously multiple times" do
          RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal 1, AcidicJob::Run.unstaged.count

          result = RideCreateJob.perform_now(@valid_user.id, @valid_params)
          assert_equal 2, AcidicJob::Run.unstaged.count

          assert_equal true, result
        end

        test "throws and stores error when step method throws exception" do
          RideCreateJob.instance_variable_set(:@error_in_create_stripe_charge, true)
          run = create_run
          AcidicJob::Run.stub(:find_by, ->(*) { run }) do
            assert_raises RideCreateJob::SimulatedTestingFailure do
              RideCreateJob.perform_now(@valid_user.id, @valid_params)
            end
          end
          RideCreateJob.instance_variable_set(:@error_in_create_stripe_charge, false)

          assert_equal [self.class.name.split("::")[0..-2], "RideCreateJob::SimulatedTestingFailure"].join("::"),
                       run.error_object.class.name
        end

        test "successfully handles Stripe card error" do
          result = RideCreateJob.perform_now(@invalid_user.id, @valid_params)
          assert_equal true, result

          # assert_enqueued_with(job: SendRideReceiptJob, args: @staged_job_params)

          assert_equal 1, AcidicJob::Run.unstaged.count
          assert_equal true, AcidicJob::Run.first.succeeded?
        end
      end
    end
  end
end
