# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

class AcidicJob::IdempotencyKey < ActiveSupport::TestCase
  include ::ActiveJob::TestHelper

  def before_setup
    Performance.reset!
    AcidicJob::Value.delete_all
    AcidicJob::Entry.delete_all
    AcidicJob::Execution.delete_all
    TestObject.delete_all
  end

  def after_teardown; end

  test "unique_by unconfigured returns job_id" do
    class WithoutAcidicIdentifier < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow { |w| w.step :step_1 }
      end

      def step_1; nil; end
    end

    job = WithoutAcidicIdentifier.new
    job.perform_now

    assert_equal job.job_id, job.unique_by
  end

  test "idempotency_key when unique_by is arguments and arguments are empty" do
    class AcidicByArguments < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: arguments) { |w| w.step :step_1 }
      end

      def step_1; nil; end
    end

    job = AcidicByArguments.new
    job.perform_now

    assert_equal "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945", job.idempotency_key
  end

  test "idempotency_key when unique_by is arguments and arguments are a static string" do
    class AcidicByBlockWithString < ActiveJob::Base
      include AcidicJob::Workflow

      def perform(*)
        execute_workflow(unique_by: arguments) { |w| w.step :step_1 }
      end

      def step_1; nil; end
    end

    job = AcidicByBlockWithString.new("a")
    job.perform_now

    assert_equal "0eb5b8d6f81bc677da8a08567cc4fa9a06a57e9ec8da85ed73a7f62727996002", job.idempotency_key
  end

  test "idempotency_key when unique_by is arguments and arguments are an array of strings" do
    class AcidicByBlockWithArrayOfStrings < ActiveJob::Base
      include AcidicJob::Workflow

      def perform(*)
        execute_workflow(unique_by: arguments) { |w| w.step :step_1 }
      end

      def step_1; nil; end
    end

    job = AcidicByBlockWithArrayOfStrings.new("a", "b")
    job.perform_now

    assert_equal "0473ef2dc0d324ab659d3580c1134e9d812035905c4781fdd6d529b0c6860e13", job.idempotency_key
  end

  test "idempotency_key when unique_by is arguments and arguments are an array of different values" do
    class AcidicByBlockWithArgValue < ActiveJob::Base
      include AcidicJob::Workflow

      def perform(*)
        execute_workflow(unique_by: arguments) { |w| w.step :step_1 }
      end

      def step_1; nil; end
    end

    job = AcidicByBlockWithArgValue.new([1, "string", { a: 1, b: 2 }, [3, 4, 5]])
    job.perform_now

    assert_equal "e493eb3be3e78cb3f40d40402c532efad9cf240d2dd6af839d37ef51a6f71aba", job.idempotency_key
  end
end
