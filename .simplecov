# frozen_string_literal: true

# SimpleCov configuration for acidic_job
# SimpleCov is started in test/test_helper.rb when COVERAGE=1

SimpleCov.configure do
  enable_coverage :branch
  primary_coverage :branch

  # Focus on the gem's code, not the test dummy app or other non-gem files
  add_filter "/test/"
  add_filter "/gemfiles/"
  add_filter "/.github/"
  add_filter "/bin/"

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
    minimum_coverage line: 80, branch: 70
    minimum_coverage_by_file line: 50, branch: 40
  end
end
