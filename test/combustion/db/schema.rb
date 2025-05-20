# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :acidic_job_executions, force: true do |t|
    t.string      :idempotency_key, null: false,  index: { unique: true }
    t.json        :serialized_job, 	null: false,  default: "{}"
    t.datetime    :last_run_at,	null: true
    t.datetime    :locked_at,	null: true
    t.string      :recover_to, null: true
    t.json        :definition,	null: true, default: "{}"

    t.timestamps
  end

  create_table :acidic_job_entries do |t|
    t.references :execution, null: false, foreign_key: { to_table: :acidic_job_executions, on_delete: :cascade }
    t.string     :step,      null: false
    t.string     :action,    null: false
    t.datetime   :timestamp, null: false
    t.json       :data,      null: true, default: "{}"

    t.timestamps
  end
  add_index :acidic_job_entries, [:execution_id, :step, :action]

  create_table :acidic_job_values do |t|
    t.references :execution, null: false, foreign_key: { to_table: :acidic_job_executions, on_delete: :cascade }
    t.string     :key,       null: false
    t.text       :value,     null: false

    t.timestamps
  end
  add_index :acidic_job_values, [:execution_id, :key], unique: true

  # -----------------------------------------------------------------------

  create_table :test_objects, force: true

  create_table :test_events do |t|
    t.references :execution, null: false, foreign_key: { to_table: :acidic_job_executions }
    t.string :name, null: false
    t.json :payload, null: false, default: "{}"
    t.datetime :started_at, null: false
    t.datetime :finished_at, null: false
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
    t.references :user, foreign_key: true
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
