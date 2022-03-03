# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

class AcidicJobGenerator < ActiveRecord::Generators::Base
  # ActiveRecord::Generators::Base inherits from Rails::Generators::NamedBase
  # which requires a NAME parameter for the new table name.
  # Our generator always uses "acidic_job_runs", so we just set a random name here.
  argument :name, type: :string, default: "random_name"

  source_root File.expand_path("templates", __dir__)

  # Copies the migration template to db/migrate.
  def copy_acidic_job_runs_migration_files
    migration_template "create_acidic_job_runs_migration.rb.erb",
                       "db/migrate/create_acidic_job_runs.rb"
  end

  protected

  def migration_class
    ActiveRecord::Migration["#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"]
  end
end
