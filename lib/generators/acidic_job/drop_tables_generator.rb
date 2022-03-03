# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module AcidicJob
	module Generators
		class DropTablesGenerator < ActiveRecord::Generators::Base
			source_root File.expand_path("../templates", __dir__)

			desc "Generates a class for a custom delivery method with the given NAME."
			
			# ActiveRecord::Generators::Base inherits from Rails::Generators::NamedBase
			# which requires a NAME parameter for the new table name.
			# Our generator always uses "acidic_job_runs", so we just set a random name here.
			argument :name, type: :string, default: "random_name"

			# Copies the migration template to db/migrate.
			def copy_acidic_job_runs_migration_files
				migration_template "drop_acidic_job_keys_migration.rb.erb",
													 "db/migrate/drop_old_acidic_job_tables.rb"
			end
			
			protected
			
			def migration_class
				ActiveRecord::Migration["#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"]
			end
		end
	end
end