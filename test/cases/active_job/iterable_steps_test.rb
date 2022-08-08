# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveJob
    class IterableSteps < ActiveSupport::TestCase
      include ::ActiveJob::TestHelper

      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
      end

      test "passing `for_each` option not in `providing` hash throws `UnknownForEachCollection` error" do
        class UnknownForEachStep < AcidicJob::Base
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something, for_each: :unknown_collection
            end
          end

          def do_something(item); end
        end

        assert_raises AcidicJob::UnknownForEachCollection do
          UnknownForEachStep.perform_now
        end
      end

      test "passing `for_each` option that isn't iterable throws `UniterableForEachCollection` error" do
        class UniterableForEachStep < AcidicJob::Base
          def perform
            with_acidic_workflow persisting: { collection: true } do |workflow|
              workflow.step :do_something, for_each: :collection
            end
          end

          def do_something(item); end
        end

        assert_raises AcidicJob::UniterableForEachCollection do
          UniterableForEachStep.perform_now
        end
      end

      test "passing valid `for_each` option iterates over collection with step method" do
        class ValidForEachStep < AcidicJob::Base
          attr_reader :processed_items

          def initialize
            @processed_items = []
            super()
          end

          def perform
            with_acidic_workflow persisting: { collection: (1..5) } do |workflow|
              workflow.step :do_something, for_each: :collection
            end
          end

          def do_something(item)
            @processed_items << item
          end
        end

        job = ValidForEachStep.new
        job.perform_now
        assert_equal [1, 2, 3, 4, 5], job.processed_items
      end

      test "can pass same `for_each` option to multiple step methods" do
        class MultipleForEachSteps < AcidicJob::Base
          attr_reader :step_one_processed_items, :step_two_processed_items

          def initialize
            @step_one_processed_items = []
            @step_two_processed_items = []
            super()
          end

          def perform
            with_acidic_workflow persisting: { items: (1..5) } do |workflow|
              workflow.step :step_one, for_each: :items
              workflow.step :step_two, for_each: :items
            end
          end

          def step_one(item)
            @step_one_processed_items << item
          end

          def step_two(item)
            @step_two_processed_items << item
          end
        end

        job = MultipleForEachSteps.new
        job.perform_now
        assert_equal [1, 2, 3, 4, 5], job.step_one_processed_items
        assert_equal [1, 2, 3, 4, 5], job.step_two_processed_items
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
