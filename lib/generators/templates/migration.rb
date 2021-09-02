class CreateAcidicJobKeys < <%= migration_class %>
  def change
    create_table :acidic_job_keys do |t|
      t.string :idempotency_key, null: false
      t.string :job_name, null: false
      t.text :job_args, null: false
      t.datetime :last_run_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :locked_at, null: true
      t.string :recovery_point, null: false
      t.text :error_object
      t.timestamps

      t.index %i[idempotency_key job_name job_args],
        unique: true,
        name: "idx_acidic_job_keys_on_idempotency_key_n_job_name_n_job_args"

    create_table :acidic_job_stagings do |t|
      t.text :serialized_params, null: false
    end
  end
end
