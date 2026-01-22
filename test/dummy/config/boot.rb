# Set up gems listed in the Gemfile.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)

# Start SimpleCov BEFORE loading any gems (including the gem under test)
# This ensures all gem code is tracked for coverage.
# Only enabled when COVERAGE=1 to avoid overhead in normal test runs.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)
