# frozen_string_literal: true

# SimpleCov configuration for acidic_job
# SimpleCov is started in test/dummy/config/boot.rb when COVERAGE=1

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

  # Merge results from parallel test runs
  merge_timeout 3600

  # Track all files in lib and app, even if not loaded during tests
  track_files "{lib,app}/**/*.rb"

  # Format the output
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])
end
