# frozen_string_literal: true

require "test_helper"
require "rails/generators"

require "generators/acidic_job/drop_tables_generator"

class DropTableGeneratorTest < Rails::Generators::TestCase
  tests AcidicJob::Generators::DropTablesGenerator
  destination File.expand_path("../tmp", __dir__)

  setup :prepare_destination

  def after_teardown
    FileUtils.rm_rf destination_root
    super
  end

  test "should generate a migration for acidic_job runs" do
    run_generator
    migration_contents = File.read(migration_file_name("db/migrate/drop_old_acidic_job_tables"))

    assert_migration "db/migrate/drop_old_acidic_job_tables"
    assert_match "drop_table :acidic_job_keys", migration_contents
    assert_match "drop_table :staged_acidic_jobs", migration_contents
  end
end
