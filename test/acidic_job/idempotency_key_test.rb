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

  test "unique_by unconfigured raises error" do
    class WithoutAcidicIdentifier < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow { |w| w.step :step_1 }
      end

      def step_1; nil; end
    end

    assert_raises(ArgumentError, "missing keyword: :unique_by") do
      WithoutAcidicIdentifier.perform_now
    end
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

    execution = AcidicJob::Execution.first

    assert_equal "bab619c21aa975baef217fbd5c6e01a7674d9d8ee3fa1c4e2a178e41d7952b23", execution.idempotency_key
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

    execution = AcidicJob::Execution.first

    assert_equal "11460654191869f08d979326233f4d4b1287b77ed069c53ac79036d96d54dd3e", execution.idempotency_key
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

    execution = AcidicJob::Execution.first

    assert_equal "76564b0604a5dfd81d1f637416e664352eda527e2cd78a806e91ad6ccd609eb3", execution.idempotency_key
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

    execution = AcidicJob::Execution.first

    assert_equal "a7c36d24b42051092df5547146952d4707bf6e04b84774576bad6a37937d018a", execution.idempotency_key
  end
end
