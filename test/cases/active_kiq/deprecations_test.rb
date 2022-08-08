# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"

# rubocop:disable Lint/ConstantDefinitionInBlock
class Cases::ActiveKiq::Deprecations < ActiveSupport::TestCase
  def before_setup
    super()
    AcidicJob::Run.delete_all
    Notification.delete_all
    Performance.reset!
    Sidekiq::Queues.clear_all
    Sidekiq.redis(&:flushdb)
  end
  
  test "deprecated `idempotently` syntax still works" do
    class Idempotently < AcidicJob::ActiveKiq
      def perform
        idempotently do
          step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    Idempotently.perform_now

    assert_equal 1, AcidicJob::Run.count
    assert_equal 1, Performance.performances
  end

  test "deprecated `with_acidity` syntax still works" do
    class WithAcidity < AcidicJob::ActiveKiq
      def perform
        with_acidity do
          step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    WithAcidity.perform_now

    assert_equal 1, AcidicJob::Run.count
    assert_equal 1, Performance.performances
  end
end
