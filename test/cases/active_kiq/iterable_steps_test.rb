# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveKiq
    class IterableSteps < ActiveSupport::TestCase
      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
        Sidekiq::Queues.clear_all
        Sidekiq.redis(&:flushdb)
      end

      test "passing `for_each` option not in `providing` hash throws `UnknownForEachCollection` error" do
        class UnknownForEachStep < AcidicJob::ActiveKiq
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
        class UniterableForEachStep < AcidicJob::ActiveKiq
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
        class ValidForEachStep < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow persisting: { collection: (1..5) } do |workflow|
              workflow.step :do_something, for_each: :collection
            end
          end

          def do_something(item)
            Performance.processed!(item)
          end
        end

        job = ValidForEachStep.new
        job.perform_now
        assert_equal [1, 2, 3, 4, 5], Performance.processed_items
      end

      test "can pass same `for_each` option to multiple step methods" do
        class MultipleForEachSteps < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow persisting: { items: (1..5) } do |workflow|
              workflow.step :step_one, for_each: :items
              workflow.step :step_two, for_each: :items
            end
          end

          def step_one(item)
            Performance.processed!(item, scope: :step_one)
          end

          def step_two(item)
            Performance.processed!(item, scope: :step_two)
          end
        end

        job = MultipleForEachSteps.new
        job.perform_now
        assert_equal [1, 2, 3, 4, 5], Performance.processed_items(:step_one)
        assert_equal [1, 2, 3, 4, 5], Performance.processed_items(:step_two)
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
