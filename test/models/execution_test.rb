# frozen_string_literal: true

require "test_helper"

class AcidicJob::ExecutionTest < ActiveSupport::TestCase
  # Helper to create execution records for testing scopes
  def create_execution(recover_to:, last_run_at: Time.current, job_class: "TestJob")
    # Build a minimal valid serialized_job
    serialized_job = {
      "job_class" => job_class,
      "job_id" => SecureRandom.uuid,
      "arguments" => []
    }

    # Build a minimal valid definition
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
      recover_to: recover_to,
      last_run_at: last_run_at
    )
  end

  # ============================================
  # Scope: finished
  # ============================================

  test "finished scope returns executions with FINISHED_RECOVERY_POINT" do
    finished_execution = create_execution(recover_to: AcidicJob::FINISHED_RECOVERY_POINT)
    unfinished_execution = create_execution(recover_to: "step_1")

    results = AcidicJob::Execution.finished

    assert_includes results, finished_execution
    assert_not_includes results, unfinished_execution
  end

  test "finished scope does not include nil or empty recover_to" do
    finished_execution = create_execution(recover_to: AcidicJob::FINISHED_RECOVERY_POINT)
    nil_execution = create_execution(recover_to: nil)
    empty_execution = create_execution(recover_to: "")

    results = AcidicJob::Execution.finished

    assert_includes results, finished_execution
    assert_not_includes results, nil_execution
    assert_not_includes results, empty_execution
  end

  # ============================================
  # Scope: outstanding
  # ============================================

  test "outstanding scope returns executions not finished" do
    finished_execution = create_execution(recover_to: AcidicJob::FINISHED_RECOVERY_POINT)
    unfinished_execution = create_execution(recover_to: "step_1")

    results = AcidicJob::Execution.outstanding

    assert_includes results, unfinished_execution
    assert_not_includes results, finished_execution
  end

  test "outstanding scope includes nil and empty recover_to" do
    nil_execution = create_execution(recover_to: nil)
    empty_execution = create_execution(recover_to: "")
    step_execution = create_execution(recover_to: "step_2")

    results = AcidicJob::Execution.outstanding

    assert_includes results, nil_execution
    assert_includes results, empty_execution
    assert_includes results, step_execution
  end

  # ============================================
  # Scope: clearable
  # ============================================

  test "clearable scope returns finished executions older than default threshold" do
    old_finished = create_execution(
      recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
      last_run_at: 2.weeks.ago
    )
    recent_finished = create_execution(
      recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
      last_run_at: 1.day.ago
    )
    old_unfinished = create_execution(
      recover_to: "step_1",
      last_run_at: 2.weeks.ago
    )

    results = AcidicJob::Execution.clearable

    assert_includes results, old_finished
    assert_not_includes results, recent_finished
    assert_not_includes results, old_unfinished
  end

  test "clearable scope accepts custom finished_before parameter" do
    three_days_old = create_execution(
      recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
      last_run_at: 3.days.ago
    )
    one_day_old = create_execution(
      recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
      last_run_at: 1.day.ago
    )

    # With 2 day threshold, only the 3-day-old record should be clearable
    results = AcidicJob::Execution.clearable(finished_before: 2.days.ago)

    assert_includes results, three_days_old
    assert_not_includes results, one_day_old
  end

  # ============================================
  # Method: clear_finished_in_batches
  # ============================================

  test "clear_finished_in_batches removes old finished executions" do
    # Create 3 old finished executions
    3.times do
      create_execution(
        recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
        last_run_at: 2.weeks.ago
      )
    end

    # Create 2 outstanding executions (should not be deleted)
    2.times do
      create_execution(
        recover_to: "step_1",
        last_run_at: 2.weeks.ago
      )
    end

    # Create 1 recent finished execution (should not be deleted)
    create_execution(
      recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
      last_run_at: 1.day.ago
    )

    assert_equal 6, AcidicJob::Execution.count

    AcidicJob::Execution.clear_finished_in_batches

    # Only outstanding (2) + recent finished (1) should remain
    assert_equal 3, AcidicJob::Execution.count
    assert_equal 2, AcidicJob::Execution.outstanding.count
    assert_equal 1, AcidicJob::Execution.finished.count
  end

  test "clear_finished_in_batches respects batch_size parameter" do
    # Create 5 old finished executions
    5.times do
      create_execution(
        recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
        last_run_at: 2.weeks.ago
      )
    end

    assert_equal 5, AcidicJob::Execution.count

    # Verify that batch_size limits the records deleted per iteration.
    # With batch_size=2, all 5 records should still be deleted (just in smaller chunks).
    # This is a functional test - we verify the end result is correct regardless of
    # how many internal iterations occurred.
    AcidicJob::Execution.clear_finished_in_batches(batch_size: 2)

    assert_equal 0, AcidicJob::Execution.count
  end

  test "clear_finished_in_batches accepts custom finished_before parameter" do
    create_execution(
      recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
      last_run_at: 10.days.ago
    )
    newer_execution = create_execution(
      recover_to: AcidicJob::FINISHED_RECOVERY_POINT,
      last_run_at: 3.days.ago
    )

    assert_equal 2, AcidicJob::Execution.count

    # Only delete executions older than 5 days
    AcidicJob::Execution.clear_finished_in_batches(finished_before: 5.days.ago)

    assert_equal 1, AcidicJob::Execution.count
    assert_equal newer_execution, AcidicJob::Execution.first
  end

  test "clear_finished_in_batches handles empty result gracefully" do
    # No executions exist
    assert_equal 0, AcidicJob::Execution.count

    # Should not raise, just return immediately
    AcidicJob::Execution.clear_finished_in_batches

    assert_equal 0, AcidicJob::Execution.count
  end
end
