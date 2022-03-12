# frozen_string_literal: true

require "active_job/test_case"
require "database_cleaner/active_record"

module AcidicJob
  class TestCase < ActiveJob::TestCase
    self.use_transactional_tests = false

    def before_setup
      super
      DatabaseCleaner.strategy = :truncation
      DatabaseCleaner.start
    end

    def after_teardown
      DatabaseCleaner.clean
      super
    end
  end
end
