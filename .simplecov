# frozen_string_literal: true

# SimpleCov configuration for acidic_job
# SimpleCov is started in bin/rails when COVERAGE=1

SimpleCov.configure do
  enable_coverage :branch
  primary_coverage :branch

  # Enable nocov comments to exclude lines from coverage
  nocov_token "nocov"

  # Use database name in command_name for proper merging across database runs
  command_name "#{ENV.fetch('TARGET_DB', 'sqlite')}-tests"

  # Focus on the gem's code, not the test dummy app or other non-gem files
  add_filter "/test/"
  add_filter "/gemfiles/"
  add_filter "/.github/"
  add_filter "/bin/"

  # Ignore gem scaffolding base classes (inherited by users, contain no logic)
  add_filter %r{app/mailers/acidic_job/application_mailer\.rb}
  add_filter %r{app/jobs/acidic_job/application_job\.rb}
  add_filter %r{app/controllers/acidic_job/application_controller\.rb}

  # Ignore trivial files
  add_filter "version.rb"
  add_filter "Rakefile"

  # Ignore test utility module (testing test utilities is meta)
  add_filter "testing.rb"

  # Group the gem's code
  add_group "Library", "lib/"
  add_group "App", "app/"

  # Configure timeout for merging coverage results (useful if tests are run in parallel)
  merge_timeout 3600

  # Track all files in lib and app, even if not loaded during tests
  track_files "{lib,app}/**/*.rb"

  # Format the output
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])

  # Minimum coverage thresholds - fail CI if coverage drops below these
  # Only enforce when running the full test suite (not during db:prepare, etc.)
  if ENV["COVERAGE_CHECK"]
    minimum_coverage line: 95, branch: 80
    minimum_coverage_by_file line: 80, branch: 0
  end
end
