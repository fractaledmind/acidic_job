SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch

  # Focus on the gem's code, not the test dummy app
  add_filter "/gemfiles/"
  add_filter "/.github/"

  # Include the main lib directory
  add_group "lib", "lib/"
  add_group "app", "app/"

  # Coverage thresholds (adjust as needed)
  # minimum_coverage 90
  # minimum_coverage_by_file 80

  # Merge results from parallel test runs
  merge_timeout 3600

  # Format the output
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])
end
