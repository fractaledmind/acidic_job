# AcidicJob Upgrade Guide

1. Update version requirements in `Gemfile`

```ruby
-gem "acidic_job"
+gem "acidic_job", "~> 1.0.0.pre1"
```

result:
```
Installing acidic_job 1.0.0.pre1 (was 0.7.7)
Bundle updated!
```

2. Generate migration for new `AcidicJob::Run` model

```bash
rails generate acidic_job
```

result:
```
create  db/migrate/#{yyyymmddhhmmss}_create_acidic_job_runs.rb
```

3. Delete any unneeded `AcidicJob::Key` records

Typically, records that are already finished do not need to be retained. Sometimes, however, applications key finished records around for some amount of time for debugging or metrics aggregation. Whatever your application's logic is for whether or not an `AcidicJob::Key` record is still needed, for all unneeded records, delete them.

For example, this would delete all finished `Key` records over 1 month old:

```ruby
AcidicJob::Key.where(recovery_point: AcidicJob::Key::RECOVERY_POINT_FINISHED, last_run_at: ..1.month.ago).delete_all
```

4. Migrate `AcidicJob::Key` to `AcidicJob::Run`

`AcidicJob` ships with an upgrade module that provides a script to migrate older `Key` records to the new `Run` model.

```ruby
AcidicJob::UpgradeService.execute
```

This script will prepare an `insert_all` command for `Run` records by mapping the older `Key` data to the new `Run` schema. It also creates the new `Run` records with the same `id` as their `Key` counterparts, and then deletes all `Key` records successfully mapped over. Any `Key` records that were failed to be mapped over will be reported, along with the exception, in the `errored_keys` portion of the resulting hash.

result:
```
{
	run_records: <Integer>,
	key_records: <Integer>,
	errored_keys: <Array>
}
```

5. Triage remaining `AcidicJob::Key` records

If there were any `AcidicJob::Key` records that failed to be mapped to the new `Run` model, you will need to manually triage whatever the exception was. In all likelihood, the exception would be relating to the translation of the `Key#job_args` field to the `Run#serialized_job` field, as all other fields have a fairly straight-forward mapping. If you can't resolve the issue, please open an Issue in GitHub.

6. Ensure all `AcidicJob::Staged` records are processed

`AcidicJob` still ships with an upgrade module that provides the older `Key` and `Staged` records, so this functionality will still be present to handle any existing records in your database when you deploy the updated version.

7. Remove the old tables

Once you have successfully migrated everything over and the new system has been running smoothly for some time, you should drop the old `acidic_job_keys` and `staged_acidic_jobs` tables. We provide a migration generator just for this purpose:

```bash
rails generate acidic_job:drop_tables
rails db:migrate
```