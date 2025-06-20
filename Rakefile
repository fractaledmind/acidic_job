require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

load "rails/tasks/statistics.rake"

require "bundler/gem_tasks"

require "minitest/test_task"
Minitest::TestTask.create :test do |t|
  t.framework = nil
end

def databases
  %w[ sqlite mysql postgres ]
end

def setup_database(database)
  ENV["TARGET_DB"] = database
  sh("TARGET_DB=#{database} bin/setup")
end

def run_test_with_database(database, test_files = nil)
  setup_database(database)

  # Ensure schema is up to date by running the db:sync task
  # sh("TARGET_DB=#{database} bin/rails db:sync")

  if test_files
    sh("TARGET_DB=#{database} bin/rails test #{test_files}")
  else
    sh("TARGET_DB=#{database} bin/rails test")
  end
end

namespace :db do
  desc "Ensure test database is in sync with latest gem migrations"
  task :sync do
    require File.expand_path("../test/dummy/config/application", __FILE__)

    template_path = File.expand_path("../lib/generators/acidic_job/templates/create_acidic_job_tables_migration.rb.erb", __FILE__)
    template_mtime = File.mtime(template_path)
    schema_path = File.expand_path("../test/dummy/db/schema.rb", __FILE__)

    Dir.chdir(File.expand_path("../test/dummy", __FILE__)) do
      migration_file = Dir["db/migrate/*_create_acidic_job_tables.rb"].first

      if migration_file.nil? ||
         File.mtime(migration_file) < template_mtime ||
         !File.exist?(schema_path)

        puts "Updating test/dummy schema..."
        FileUtils.rm_f(migration_file) if migration_file
        FileUtils.rm_f(schema_path)

        sh("bin/rails db:environment:set RAILS_ENV=test")
        sh("bin/rails db:drop")
        sh("bin/rails generate acidic_job:install")
        sh("bin/rails db:migrate")
      end

      sh("bin/rails db:test:prepare")
    end
  end
end

# Hook into the `test:prepare` task hook provided by Rails
namespace :test do
  task prepare: :environment do
    Rake::Task["db:sync"].invoke
  end
end

namespace :test do
  desc "Run all tests against all databases"
  task :all do
    test_files = ENV["TEST"]

    if test_files
      puts "Running specific test(s): #{test_files}"
    else
      puts "Running all tests"
    end

    databases.each do |database|
      puts "\n" + "="*60
      puts "Running #{test_files ? 'specific test(s)' : 'all tests'} against #{database.upcase}"
      puts "="*60
      run_test_with_database(database, test_files)
    end
  end

  # Individual database tasks
  databases.each do |database|
    desc "Run tests against #{database}"
    task database.to_sym do
      test_files = ENV["TEST"]

      puts "\n" + "="*60
      puts "Running #{test_files ? 'specific test(s)' : 'all tests'} against #{database.upcase}"
      puts "="*60

      run_test_with_database(database, test_files)
    end
  end

  # Convenience aliases
  task pg: :postgres
  task postgresql: :postgres
end

# Help task to show usage examples
task :help do
  puts <<~HELP
    AcidicJob Test Runner - Usage Examples:

    All tests against all databases:
      rake test:all
      rake test              # backward compatibility

    All tests against one database:
      rake test:sqlite
      rake test:mysql
      rake test:postgres     # or rake test:pg

    One test against all databases:
      rake test:all TEST=test/jobs/delaying_job_test.rb
      rake test:all TEST=test/jobs/delaying_job_test.rb:6

    One test against one database:
      rake test:mysql TEST=test/jobs/delaying_job_test.rb
      rake test:postgres TEST=test/jobs/delaying_job_test.rb:6

    Multiple tests against one database:
      rake test:sqlite TEST="test/jobs/delaying_job_test.rb test/jobs/other_test.rb"

    Database setup only (without running tests):
      TARGET_DB=mysql bin/setup

    Show this help:
      rake help

    Notes:
    - Docker containers for MySQL/PostgreSQL are automatically started when needed
    - Test schema is automatically synced with migration generator before running tests
    - Use TEST environment variable to specify specific test files or line numbers
  HELP
end
