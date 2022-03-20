# frozen_string_literal: true

require "active_record"
require "global_id"
require "minitest/mock"
require "logger"
require "sqlite3"
require "database_cleaner"
require "noticed"

# DATABASE AND MODELS ----------------------------------------------------------
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: "database.sqlite",
  flags: SQLite3::Constants::Open::READWRITE |
         SQLite3::Constants::Open::CREATE |
         SQLite3::Constants::Open::SHAREDCACHE
)

GlobalID.app = :test
DatabaseCleaner.clean_with(:truncation)

ActiveRecord::Schema.define do
  create_table :acidic_job_runs, force: true do |t|
    t.boolean :staged, null: false,	default: false
    t.string :idempotency_key, null: false
    t.text :serialized_job,	null: false
    t.string :job_class,	null: false
    t.datetime :last_run_at,	null: true,	default: -> { "CURRENT_TIMESTAMP" }
    t.datetime :locked_at,	null: true
    t.string :recovery_point,	null: true
    t.text :error_object,	null: true
    t.text :attr_accessors,	null: true
    t.text :workflow,	null: true
    t.timestamps

    t.index :idempotency_key, unique: true
  end

  # -----------------------------------------------------------------------

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
    t.references :user, foreign_key: true, on_delete: :restrict
    t.timestamps
  end

  create_table :notifications, force: :cascade do |t|
    t.string :recipient_type, null: false
    t.bigint :recipient_id, null: false
    t.string :type
    t.json :params
    t.datetime :read_at
    t.timestamps
    t.index %i[recipient_type recipient_id], name: "index_notifications_on_recipient_type_and_recipient_id"
  end
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  include GlobalID::Identification
end

class Audit < ApplicationRecord
  belongs_to :auditable, polymorphic: true
  belongs_to :associated, polymorphic: true
  belongs_to :user, polymorphic: true
end

class User < ApplicationRecord
  has_many :notifications, as: :recipient

  validates :email, presence: true
  validates :stripe_customer_id, presence: true
end

class Ride < ApplicationRecord
  belongs_to :user
end

class Notification < ApplicationRecord
  include Noticed::Model
end

DatabaseCleaner.clean_with(:deletion, except: %w[users])

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

ActiveRecord::Base.logger = Logger.new(IO::NULL) # Logger.new($stdout) #

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
