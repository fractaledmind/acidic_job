# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"
require "rails/version"

p({ruby: RUBY_VERSION, rails: Rails::VERSION::STRING})

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

require "warning"
Warning.ignore(%i[not_reached unused_var])

require "acidic_job"
require "minitest/autorun"

require "combustion"
Combustion.path = "test"
Combustion.initialize!

require_relative "support/setup"
