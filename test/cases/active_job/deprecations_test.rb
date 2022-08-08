# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
class Cases::ActiveJob::Deprecations < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def before_setup
    super()
    AcidicJob::Run.delete_all
    Notification.delete_all
    Performance.reset!
  end
  
  test "deprecated `idempotently` syntax still works" do
    class Idempotently < AcidicJob::Base
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
    class WithAcidity < AcidicJob::Base
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