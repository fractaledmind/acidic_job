# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :acidic_job_runs, force: true do |t|
    t.boolean     :staged,          null: false,  default: false
    t.string      :idempotency_key, null: false,  index: { unique: true }
    t.text        :serialized_job,  null: false
    t.string      :job_class,       null: false
    t.datetime    :last_run_at,     null: true, default: -> { "CURRENT_TIMESTAMP" }
    t.datetime    :locked_at,       null: true
    t.string      :recovery_point,  null: true
    t.text        :error_object,    null: true
    t.text        :attr_accessors,  null: true
    t.text        :workflow,        null: true
    t.references  :awaited_by,      null: true, index: true
    t.text        :returning_to,    null: true
    t.timestamps
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
