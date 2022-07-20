# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"
require "rails/version"

p({ ruby: RUBY_VERSION, rails: Rails::VERSION::STRING })

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
Combustion.path = "test/combustion"
Combustion.initialize! :active_record do
  # https://discuss.rubyonrails.org/t/cve-2022-32224-possible-rce-escalation-bug-with-serialized-columns-in-active-record/81017
  config.active_record.use_yaml_unsafe_load = true
end
require_relative "support/setup"