# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "acidic_job"

require "simplecov"
SimpleCov.start

require "minitest/autorun"

require "database_cleaner/active_record"

DatabaseCleaner.strategy = [:deletion, { except: %w[users] }]
