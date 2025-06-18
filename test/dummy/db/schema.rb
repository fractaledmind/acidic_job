# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_05_22_154837) do
  create_table "acidic_job_entries", force: :cascade do |t|
    t.bigint "execution_id", null: false
    t.string "step", null: false
    t.string "action", null: false
    t.datetime "timestamp", null: false
    t.text "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "execution_id", "step", "action" ], name: "index_acidic_job_entries_on_execution_id_and_step_and_action"
    t.index [ "execution_id" ], name: "index_acidic_job_entries_on_execution_id"
  end

  create_table "acidic_job_executions", force: :cascade do |t|
    t.string "idempotency_key", null: false
    t.json "serialized_job", null: false
    t.datetime "last_run_at"
    t.datetime "locked_at"
    t.string "recover_to"
    t.text "definition"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "idempotency_key" ], name: "index_acidic_job_executions_on_idempotency_key", unique: true
  end

  create_table "acidic_job_values", force: :cascade do |t|
    t.bigint "execution_id", null: false
    t.string "key", null: false
    t.text "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "execution_id", "key" ], name: "index_acidic_job_values_on_execution_id_and_key", unique: true
    t.index [ "execution_id" ], name: "index_acidic_job_values_on_execution_id"
  end

  create_table :things, force: true

  add_foreign_key "acidic_job_entries", "acidic_job_executions", column: "execution_id", on_delete: :cascade
  add_foreign_key "acidic_job_values", "acidic_job_executions", column: "execution_id", on_delete: :cascade
end
