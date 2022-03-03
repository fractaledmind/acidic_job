# frozen_string_literal: true

require "rails/generators/active_record"

module AcidicJob
	module Generators
		class DropTablesGenerator < ::Rails::Generators::Base
			include ActiveRecord::Generators::Migration
			source_root File.expand_path("templates", __dir__)

			desc "Drops the pre-1.0 tables for the AcidicJob::Key and AcidicJob::Staged models."

			def copy_migration
				migration_template "drop_acidic_job_keys_migration.rb.erb",
													 "db/migrate/drop_old_acidic_job_tables.rb",
													 migration_version: migration_version
			end
			
			protected
			
			def migration_version
				"[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
			end
		end
	end
end