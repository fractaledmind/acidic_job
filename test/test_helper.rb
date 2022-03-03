# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

require 'warning'
Warning.ignore([:not_reached, :unused_var])

require "acidic_job"
require "minitest/autorun"
require "combustion"
Combustion.path = "test/dummy"
Combustion.initialize! :action_mailer
require_relative "support/setup"
