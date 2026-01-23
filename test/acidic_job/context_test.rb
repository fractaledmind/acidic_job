# frozen_string_literal: true

require "test_helper"

class AcidicJob::ContextTest < ActiveSupport::TestCase
  def create_execution
    serialized_job = {
      "job_class" => "TestJob",
      "job_id" => SecureRandom.uuid,
      "arguments" => []
    }
    definition = {
      "meta" => { "version" => AcidicJob::VERSION },
      "steps" => {
        "step_1" => { "does" => "step_1", "then" => AcidicJob::FINISHED_RECOVERY_POINT }
      }
    }
    AcidicJob::Execution.create!(
      idempotency_key: SecureRandom.hex(32),
      serialized_job: serialized_job,
      definition: definition,
      recover_to: "step_1"
    )
  end

  # ============================================
  # set
  # ============================================

  test "set stores a single key-value pair" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)

    context.set(foo: "bar")

    assert_equal 1, execution.values.count
    assert_equal "bar", execution.values.find_by(key: "foo").value
  end

  test "set stores multiple key-value pairs" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)

    context.set(foo: "bar", baz: 123, qux: [ 1, 2, 3 ])

    assert_equal 3, execution.values.count
    assert_equal "bar", execution.values.find_by(key: "foo").value
    assert_equal 123, execution.values.find_by(key: "baz").value
    assert_equal [ 1, 2, 3 ], execution.values.find_by(key: "qux").value
  end

  test "set upserts existing keys" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)

    context.set(foo: "original")
    context.set(foo: "updated")

    assert_equal 1, execution.values.count
    assert_equal "updated", execution.values.find_by(key: "foo").value
  end

  # ============================================
  # get
  # ============================================

  test "get retrieves a single value" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)
    context.set(foo: "bar")

    result = context.get(:foo)

    assert_equal [ "bar" ], result
  end

  test "get retrieves multiple values" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)
    context.set(foo: "bar", baz: 123)

    result = context.get(:foo, :baz)

    # Order is not guaranteed, so check both values are present
    assert_equal 2, result.size
    assert_includes result, "bar"
    assert_includes result, 123
  end

  test "get returns empty array for non-existent key" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)

    result = context.get(:nonexistent)

    assert_equal [], result
  end

  # ============================================
  # fetch
  # ============================================

  test "fetch returns existing value" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)
    context.set(foo: "existing")

    result = context.fetch(:foo, "default")

    assert_equal "existing", result
  end

  test "fetch uses default when key does not exist" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)

    result = context.fetch(:foo, "default")

    assert_equal "default", result
    # Should also store the default
    assert_equal "default", execution.values.find_by(key: "foo").value
  end

  test "fetch uses block when key does not exist and no default" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)

    result = context.fetch(:foo) { |key| "computed_#{key}" }

    assert_equal "computed_foo", result
    assert_equal "computed_foo", execution.values.find_by(key: "foo").value
  end

  # ============================================
  # []= and []
  # ============================================

  test "[]= sets a value" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)

    context[:foo] = "bar"

    assert_equal "bar", execution.values.find_by(key: "foo").value
  end

  test "[] gets a value" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)
    context.set(foo: "bar")

    result = context[:foo]

    assert_equal "bar", result
  end

  test "[] returns nil for non-existent key" do
    execution = create_execution
    context = AcidicJob::Context.new(execution)

    result = context[:nonexistent]

    assert_nil result
  end

  # ============================================
  # Integration with workflow
  # ============================================

  # This test verifies that workflow context values persist across job retries.
  #
  # How it works:
  # 1. First execution (executions=1): set_context stores attempt=1, then raises DefaultsError
  # 2. retry_on triggers a retry, incrementing the job's `executions` counter to 2
  # 3. Second execution (executions=2): set_context stores attempt=2 (overwriting), completes successfully
  # 4. read_context runs and logs the final context values
  #
  # The assertion checks that attempt=2 because set_context ran twice (once per execution),
  # each time storing the current `executions` value. The nested data persists unchanged
  # since it was set identically in both executions.
  test "context persists across job retries" do
    class ContextRetryJob < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :set_context
          w.step :read_context
        end
      end

      def set_context
        ctx[:attempt] = executions
        ctx[:data] = { nested: "value" }
        raise DefaultsError if executions == 1
      end

      def read_context
        ChaoticJob.log_to_journal!({
          "attempt" => ctx[:attempt],
          "data" => ctx[:data]
        })
      end
    end

    ContextRetryJob.perform_later
    perform_all_jobs

    entry = ChaoticJob.top_journal_entry
    # After retry, attempt=2 because set_context ran twice, storing executions each time
    assert_equal 2, entry["attempt"]
    assert_equal "value", entry["data"][:nested]
  end
end
