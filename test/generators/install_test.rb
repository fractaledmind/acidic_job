# frozen_string_literal: true

require "test_helper"
require "rails/generators"

require "generators/acidic_job/install_generator"

class AcidicJobGeneratorTest < Rails::Generators::TestCase
  tests AcidicJob::Generators::InstallGenerator
  destination File.expand_path("../tmp", __dir__)

  setup :prepare_destination

  def after_teardown
    FileUtils.rm_rf destination_root
    super
  end

  test "should generate a migration for acidic_job tables" do
    run_generator
    migration_contents = File.read(migration_file_name("db/migrate/create_acidic_job_tables"))

    assert_migration "db/migrate/create_acidic_job_tables"
    assert_match "create_table :acidic_job_executions", migration_contents
    assert_match "create_table :acidic_job_entries", migration_contents
    assert_match "create_table :acidic_job_values", migration_contents
  end
end
