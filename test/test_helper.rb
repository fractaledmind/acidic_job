# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

require "acidic_job"
require "minitest/autorun"

require "database_cleaner/active_record"

DatabaseCleaner.strategy = [:deletion, { except: %w[users] }]
