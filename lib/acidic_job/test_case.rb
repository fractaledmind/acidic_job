# frozen_string_literal: true

require "active_job/test_case"
require "database_cleaner/active_record"

module AcidicJob
  class TestCase < ActiveJob::TestCase
    self.use_transactional_tests = false if self.respond_to?(:use_transactional_tests)

    def before_setup
      @original_cleaners = DatabaseCleaner.cleaners
      DatabaseCleaner.cleaners = transaction_free_cleaners_for(@original_cleaners)
      super
      DatabaseCleaner.start
    end

    def after_teardown
      DatabaseCleaner.clean
      super
      DatabaseCleaner.cleaners = @original_cleaners
    end

    private

    # Ensure that the system's original DatabaseCleaner configuration is maintained, options included,
    # except that any `transaction` strategies for any ORMs are replaced with a `deletion` strategy.
    def transaction_free_cleaners_for(original_cleaners)
      non_transaction_cleaners = original_cleaners.dup.map do |(orm, opts), cleaner|
        [[orm, opts], ensure_no_transaction_strategies_for(cleaner)]
      end.to_h
      DatabaseCleaner::Cleaners.new(non_transaction_cleaners)
    end

    def ensure_no_transaction_strategies_for(cleaner)
      return cleaner unless strategy_name_for(cleaner) == "transaction"

      cleaner.strategy = deletion_strategy_for(cleaner)
      cleaner
    end

    def strategy_name_for(cleaner)
      cleaner               # <DatabaseCleaner::Cleaner>
        .strategy           # <DatabaseCleaner::ActiveRecord::Truncation>
        .class              # DatabaseCleaner::ActiveRecord::Truncation
        .name               # "DatabaseCleaner::ActiveRecord::Truncation"
        .rpartition('::')   # ["DatabaseCleaner::ActiveRecord", "::", "Truncation"]
        .last               # "Truncation"
        .downcase           # "truncation"
    end

    def deletion_strategy_for(cleaner)
      strategy = cleaner.strategy
      strategy_namespace = strategy # <DatabaseCleaner::ActiveRecord::Truncation>
        .class                      # DatabaseCleaner::ActiveRecord::Truncation
        .name                       # "DatabaseCleaner::ActiveRecord::Truncation"
        .rpartition('::')           # ["DatabaseCleaner::ActiveRecord", "::", "Truncation"]
        .first                      # "DatabaseCleaner::ActiveRecord"
      deletion_strategy_class_name = [strategy_namespace, "::", "Deletion"].join
      deletion_strategy_class = deletion_strategy_class_name.constantize
      instance_variable_hash = strategy.instance_variables.map do |var|
        [
          var.to_s.remove('@'), 
          strategy.instance_variable_get(var)
        ]
      end.to_h
      options = instance_variable_hash.except('db', 'connection_class')

      deletion_strategy_class.new(**options)
    end
  end
end
