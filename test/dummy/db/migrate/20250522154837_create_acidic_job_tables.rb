class CreateAcidicJobTables < ActiveRecord::Migration[8.0]
  def change
    create_table :acidic_job_executions, id: :primary_key do |t|
      t.string      :idempotency_key, null: false,  index: { unique: true }
      t.json        :serialized_job, 	null: false
      t.datetime    :last_run_at, 		null: true
      t.datetime    :locked_at, 			null: true
      t.string      :recover_to, 	    null: true
      t.text        :definition, 			null: true

      t.timestamps
    end

    create_table :acidic_job_entries, id: :primary_key do |t|
      t.references :execution, null: false,
        type: :bigint,
        foreign_key: { to_table: :acidic_job_executions, on_delete: :cascade }
      t.string     :step,      null: false
      t.string     :action,    null: false
      t.datetime   :timestamp, null: false
      t.text       :data,      null: true

      t.timestamps
    end
    add_index :acidic_job_entries, [:execution_id, :step, :action]

    create_table :acidic_job_values, id: :primary_key do |t|
      t.references :execution, null: false,
        type: :bigint,
        foreign_key: { to_table: :acidic_job_executions, on_delete: :cascade }
      t.string     :key,       null: false
      t.text       :value,     null: false

      t.timestamps
    end
    add_index :acidic_job_values, [:execution_id, :key], unique: true
  end
end
