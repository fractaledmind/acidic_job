# frozen_string_literal: true

require "test_helper"

class AcidicJob::EntryTest < ActiveSupport::TestCase
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

  def create_entry(execution, step:, action:, timestamp: Time.current)
    AcidicJob::Entry.create!(
      execution: execution,
      step: step,
      action: action,
      timestamp: timestamp,
      data: {}
    )
  end

  # ============================================
  # Scope: for_step
  # ============================================

  test "for_step scope filters by step name" do
    execution = create_execution
    step1_entry = create_entry(execution, step: "step_1", action: "started")
    step2_entry = create_entry(execution, step: "step_2", action: "started")

    results = AcidicJob::Entry.for_step("step_1")

    assert_includes results, step1_entry
    assert_not_includes results, step2_entry
  end

  # ============================================
  # Scope: for_action
  # ============================================

  test "for_action scope filters by action" do
    execution = create_execution
    started_entry = create_entry(execution, step: "step_1", action: "started")
    succeeded_entry = create_entry(execution, step: "step_1", action: "succeeded")

    results = AcidicJob::Entry.for_action("started")

    assert_includes results, started_entry
    assert_not_includes results, succeeded_entry
  end

  # ============================================
  # Scope: ordered
  # ============================================

  test "ordered scope sorts by timestamp ascending" do
    execution = create_execution
    early = create_entry(execution, step: "step_1", action: "started", timestamp: 2.minutes.ago)
    late = create_entry(execution, step: "step_1", action: "succeeded", timestamp: 1.minute.ago)

    results = AcidicJob::Entry.ordered

    assert_equal [ early, late ], results.to_a
  end

  # ============================================
  # Class method: most_recent
  # ============================================

  test "most_recent returns the most recently created entry" do
    execution = create_execution

    # Explicitly set created_at timestamps to avoid relying on database clock ordering
    first = create_entry(execution, step: "step_1", action: "started")
    first.update_column(:created_at, 2.minutes.ago)

    second = create_entry(execution, step: "step_1", action: "succeeded")
    second.update_column(:created_at, 1.minute.ago)

    result = AcidicJob::Entry.most_recent

    assert_equal second, result
  end

  test "most_recent returns nil when no entries exist" do
    result = AcidicJob::Entry.most_recent

    assert_nil result
  end

  # ============================================
  # Instance method: action?
  # ============================================

  test "action? returns true when action matches" do
    execution = create_execution
    entry = create_entry(execution, step: "step_1", action: "started")

    assert entry.action?("started")
  end

  test "action? returns false when action does not match" do
    execution = create_execution
    entry = create_entry(execution, step: "step_1", action: "started")

    assert_not entry.action?("succeeded")
  end
end
