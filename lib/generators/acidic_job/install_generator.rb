# frozen_string_literal: true

require "rails/generators/active_record"

module AcidicJob
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      desc "Generates a migration for the AcidicJob tables."

      # Copies the migration template to db/migrate.
      def copy_acidic_job_runs_migration_files
        migration_template(
          "create_acidic_job_tables_migration.rb.erb",
          "db/migrate/create_acidic_job_tables.rb",
          migration_version: migration_version
        )
      end

      protected def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
