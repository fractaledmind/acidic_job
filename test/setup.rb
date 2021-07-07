# frozen_string_literal: true

require "active_record"
require "active_job"
require "minitest"
require "minitest/mock"
require "logger"
require "sqlite3"

# DATABASE AND MODELS ----------------------------------------------------------
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: "test/database.sqlite",
  flags: SQLite3::Constants::Open::READWRITE |
         SQLite3::Constants::Open::CREATE |
         SQLite3::Constants::Open::SHAREDCACHE
)

DatabaseCleaner.clean_with :truncation

# rubocop:disable Metrics/BlockLength
ActiveRecord::Schema.define do
  create_table :acidic_job_keys, force: true do |t|
    t.string :job_name, null: false
    t.text :job_args, null: false
    t.string :idempotency_key, null: false
    t.datetime :last_run_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    t.datetime :locked_at, null: true
    t.string :recovery_point, null: false
    t.text :error_object
    t.timestamps

    t.index %i[idempotency_key job_name job_args], unique: true,
                                                   name: "idx_acidic_job_keys_on_idempotency_key_n_job_name_n_job_args"
  end

  create_table :audits, force: true do |t|
    t.references :auditable, polymorphic: true
    t.references :associated, polymorphic: true
    t.references :user, polymorphic: true
    t.string :username
    t.string :action
    t.text :audited_changes
    t.integer :version, default: 0
    t.string :comment
    t.string :remote_address
    t.string :request_uuid
    t.timestamps

    t.index %i[auditable_type auditable_id version]
    t.index %i[associated_type associated_id]
    t.index %i[user_id user_type]
    t.index :request_uuid
  end

  create_table :users, force: true do |t|
    t.string :email, null: false
    t.string :stripe_customer_id, null: false
    t.timestamps
  end

  create_table :rides, force: true do |t|
    t.integer :origin_lat
    t.integer :origin_lon
    t.integer :target_lat
    t.integer :target_lon
    t.string :stripe_charge_id
    t.references :acidic_job_key, foreign_key: true, null: true, on_delete: :nullify
    t.references :user, foreign_key: true, on_delete: :restrict
    t.timestamps

    t.index %i[user_id acidic_job_key_id], unique: true
  end

  create_table :staged_jobs, force: true do |t|
    t.string :job_name, null: false
    t.text :job_args, null: false
    t.timestamps
  end
end
# rubocop:enable Metrics/BlockLength

class AcidicJobKey < ActiveRecord::Base
  RECOVERY_POINT_FINISHED = "FINISHED"

  serialize :job_args, Hash
  serialize :error_object

  validates :job_name, presence: true
  validates :job_args, presence: true
  validates :idempotency_key, presence: true
  validates :last_run_at, presence: true
  validates :recovery_point, presence: true

  def finished?
    recovery_point == RECOVERY_POINT_FINISHED
  end

  def succeeded?
    finished? && !failed?
  end

  def failed?
    error_object.present?
  end
end

class Audit < ActiveRecord::Base
  belongs_to :auditable, polymorphic: true
  belongs_to :associated, polymorphic: true
  belongs_to :user, polymorphic: true
end

class User < ActiveRecord::Base
  validates :email, presence: true
  validates :stripe_customer_id, presence: true
end

class Ride < ActiveRecord::Base
  belongs_to :user
  belongs_to :acidic_job_key, optional: true
end

class StagedJob < ActiveRecord::Base
  validates :job_name, presence: true
  validates :job_args, presence: true
end

# SEEDS ------------------------------------------------------------------------

USERS = [
  ["user@example.com", "tok_visa"],
  ["user-bad-source@example.com", "tok_chargeCustomerFail"]
].freeze

USERS.each do |(email, stripe_source)|
  User.create!(email: email,
               stripe_customer_id: stripe_source)
end

# LOGGING ----------------------------------------------------------------------

ActiveRecord::Base.logger = Logger.new(IO::NULL) # Logger.new($stdout)
ActiveJob::Base.logger = Logger.new(IO::NULL) # Logger.new($stdout)

# MOCKS ------------------------------------------------------------------------

module Stripe
  class CardError < StandardError; end

  class StripeError < StandardError; end

  class Charge
    def self.create(params, _args)
      raise CardError, "Your card was declined." if params[:customer] == "tok_chargeCustomerFail"

      charge_struct = Struct.new(:id)
      charge_struct.new(123)
    end
  end
end

# TEST JOB ------------------------------------------------------------------------

class RideCreateJob < ActiveJob::Base
  self.log_arguments = false

  include AcidicJob

  class MissingRideAtRideCreatedRecoveryPoint < StandardError; end

  class SimulatedTestingFailure < StandardError; end

  attr_accessor :ride

  required :user, :params

  def perform(idempotency_key, user, ride_params)
    idempotently key: idempotency_key, with: { user: user, params: ride_params } do
      step :create_ride_and_audit_record
      step :create_stripe_charge
      step :send_receipt
    end
  end

  private

  # rubocop:disable Metrics/MethodLength
  def create_ride_and_audit_record
    ride = Ride.create!(
      acidic_job_key_id: key.id,
      origin_lat: params["origin_lat"],
      origin_lon: params["origin_lon"],
      target_lat: params["target_lat"],
      target_lon: params["target_lon"],
      stripe_charge_id: nil, # no charge created yet
      user: user
    )

    # in the same transaction insert an audit record for what happened
    Audit.create!(
      action: :AUDIT_RIDE_CREATED,
      auditable: ride,
      user: user,
      audited_changes: params
    )
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/MethodLength
  def create_stripe_charge
    # retrieve a ride record if necessary (i.e. we're recovering)
    ride = Ride.find_by(acidic_job_key_id: key.id) if ride.nil?

    # if ride is still nil by this point, we have a bug
    raise MissingRideAtRideCreatedRecoveryPoint if ride.nil?

    raise SimulatedTestingFailure if defined?(raise_error)

    # Rocket Rides is still a new service, so during our prototype phase
    # we're going to give $20 fixed-cost rides to everyone, regardless of
    # distance. We'll implement a better algorithm later to better
    # represent the cost in time and jetfuel on the part of our pilots.
    charge = Stripe::Charge.create({
                                     amount: 20_00,
                                     currency: "usd",
                                     customer: user.stripe_customer_id,
                                     description: "Charge for ride #{ride.id}"
                                   }, {
                                     # Pass through our own unique ID rather than the value
                                     # transmitted to us so that we can guarantee uniqueness to Stripe
                                     # across all Rocket Rides accounts.
                                     idempotency_key: "rocket-rides-atomic-#{key.id}"
                                   })

    ride.update(stripe_charge_id: charge.id)
  end
  # rubocop:enable Metrics/MethodLength

  def send_receipt
    # Send a receipt asynchronously by adding an entry to the staged_jobs
    # table. By funneling the job through Postgres, we make this
    # operation transaction-safe.
    StagedJob.create!(
      job_name: "send_ride_receipt",
      job_args: {
        amount: 20_00,
        currency: "usd",
        user_id: user.id
      }
    )
  end
end
