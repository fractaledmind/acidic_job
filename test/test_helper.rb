# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

require "acidic_job"
require "minitest/autorun"
require_relative "support/setup"
