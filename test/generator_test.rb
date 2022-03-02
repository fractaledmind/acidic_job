# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "generators/acidic_job_generator"

class AcidicJobGeneratorTest < Rails::Generators::TestCase
  tests AcidicJobGenerator
  destination File.expand_path("../tmp", __dir__)

  setup :prepare_destination

  def after_teardown
    FileUtils.rm_rf destination_root
    super
  end

  test "should generate a migration for acidic_job runs" do
    run_generator
    migration_contents = File.read(migration_file_name("db/migrate/create_acidic_job_runs"))

    assert_migration "db/migrate/create_acidic_job_runs"
    assert_match "create_table :acidic_job_runs", migration_contents
  end
end
