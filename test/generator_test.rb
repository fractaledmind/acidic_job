require "test_helper"
require "rails/generators"
require "generators/acidic_job_generator"

class AcidicJobGeneratorTest < Rails::Generators::TestCase
  tests AcidicJobGenerator
  destination File.expand_path("../../tmp", __FILE__)

  setup :prepare_destination

  test "should generate a migration" do
    run_generator
    migration_contents = File.read(migration_file_name("db/migrate/create_acidic_job_keys"))

    assert_migration "db/migrate/create_acidic_job_keys"
    assert_match "create_table :acidic_job_keys", migration_contents
  ensure
    FileUtils.rm_rf destination_root
  end
end
