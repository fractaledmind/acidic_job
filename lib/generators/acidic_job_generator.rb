# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

class AcidicJobGenerator < ActiveRecord::Generators::Base
  # ActiveRecord::Generators::Base inherits from Rails::Generators::NamedBase
  # which requires a NAME parameter for the new table name.
  # Our generator always uses "acidic_job_runs", so we just set a random name here.
  argument :name, type: :string, default: "random_name"

  source_root File.expand_path("templates", __dir__)

  def self.next_migration_number(_path)
    if instance_variable_defined?("@prev_migration_nr")
      @prev_migration_nr += 1
    else
      @prev_migration_nr = Time.now.utc.strftime("%Y%m%d%H%M%S").to_i
    end

    @prev_migration_nr.to_s
  end

  # Copies the migration template to db/migrate.
  def copy_acidic_job_runs_migration_files
    migration_template "create_acidic_job_runs_migration.rb.erb",
                       "db/migrate/create_acidic_job_runs.rb"
  end

  protected

  def migration_class
    if ActiveRecord::VERSION::MAJOR >= 5
      ActiveRecord::Migration["#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"]
    else
      ActiveRecord::Migration
    end
  end
end
