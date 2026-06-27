# frozen_string_literal: true

require "test_helper"

# `commit:` declares a step's "consequence" — a method run transactionally with
# the step's completion. The consequence, the `succeeded` entry, and the advance
# of the recovery cursor all commit in a single transaction, so a projection
# written by the consequence can never drift from the recorded progression.
class AcidicJob::CommitTest < ActiveJob::TestCase
  # ============================================
  # Validation
  # ============================================

  class BadValueJob < ActiveJob::Base
    include AcidicJob::Workflow

    def perform
      execute_workflow(unique_by: job_id) do |w|
        w.step :do_work, commit: 123
      end
    end

    def do_work; end
  end

  test "rejects a commit value that is not a method name" do
    error = assert_raises(ArgumentError) { BadValueJob.perform_now }
    assert_match(/must be a method name/, error.message)
  end

  class UndefinedConsequenceJob < ActiveJob::Base
    include AcidicJob::Workflow

    def perform
      execute_workflow(unique_by: job_id) do |w|
        w.step :do_work, commit: :nonexistent
      end
    end

    def do_work; end
  end

  test "raises when the consequence method is undefined" do
    assert_raises(AcidicJob::UndefinedMethodError) { UndefinedConsequenceJob.perform_now }
  end

  class ArityConsequenceJob < ActiveJob::Base
    include AcidicJob::Workflow

    def perform
      execute_workflow(unique_by: job_id) do |w|
        w.step :do_work, commit: :needs_arg
      end
    end

    def do_work; end
    def needs_arg(_x); end
  end

  test "raises when the consequence method requires arguments" do
    assert_raises(AcidicJob::InvalidMethodError) { ArityConsequenceJob.perform_now }
  end

  # ============================================
  # Behavior
  # ============================================

  class CommitJob < ActiveJob::Base
    include AcidicJob::Workflow

    def perform
      execute_workflow(unique_by: job_id) do |w|
        w.step :step_one, commit: :commit_one
        w.step :step_two, commit: :commit_two
      end
    end

    # idempotent bodies (Set-backed journal) standing in for external IO
    def step_one = ChaoticJob.log_to_journal!(:one)
    def step_two = ChaoticJob.log_to_journal!(:two)

    # NON-idempotent consequences: each call creates a new row. Exactly-once is
    # guaranteed by the atomic commit, NOT by the consequence being idempotent.
    def commit_one = Thing.create!
    def commit_two = Thing.create!
  end

  test "runs each consequence atomically with its step, leaving no extra bookkeeping" do
    CommitJob.perform_later
    perform_all_jobs

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    # the consequence leaves no trace in the entry stream — it is atomic with the
    # `succeeded` entry, so the stream looks exactly like a plain workflow
    assert_equal(
      [
        %w[step_one started],
        %w[step_one succeeded],
        %w[step_two started],
        %w[step_two succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # one projection per committed step
    assert_equal 2, Thing.count
  end

  class RollbackJob < ActiveJob::Base
    include AcidicJob::Workflow

    def perform
      execute_workflow(unique_by: job_id) do |w|
        w.step :do_work, commit: :project
      end
    end

    def do_work = ChaoticJob.log_to_journal!(:worked)

    def project
      Thing.create!
      raise BreakingError, "consequence failed after projecting"
    end
  end

  test "rolls back the projection AND the succeeded entry together when the consequence fails" do
    assert_raises(BreakingError) { RollbackJob.perform_now }

    execution = AcidicJob::Execution.first

    # the projection was rolled back atomically with the succeeded entry...
    assert_equal 0, Thing.count
    refute execution.entries.for_step("do_work").for_action("succeeded").exists?
    # ...the step is recorded as errored, and the cursor never advanced
    assert execution.entries.for_step("do_work").for_action("errored").exists?
    assert_equal "do_work", execution.recover_to
  end

  # ============================================
  # Chaos: edge cases under injected failures
  # ============================================

  class SingleCommitJob < ActiveJob::Base
    include AcidicJob::Workflow

    def perform
      execute_workflow(unique_by: job_id) do |w|
        w.step :do_work, commit: :project
      end
    end

    def do_work = ChaoticJob.log_to_journal!(:worked)
    def project = Thing.create!
  end

  test "consequence is exactly-once even when it crashes after executing but before commit" do
    # glitch fires AFTER `project` runs `Thing.create!` but BEFORE it returns —
    # i.e. inside the commit transaction. The strict guarantee: that executed
    # `Thing.create!` is rolled back, then replayed, netting exactly one row.
    run_scenario(
      SingleCommitJob.new,
      glitch: glitch_before_return("#{SingleCommitJob.name}#project")
    ) do
      perform_all_jobs
    end

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    assert_equal 1, Thing.count
  end

  # Exhaustively inject a failure before every call/return/line within the job
  # and assert the atomicity invariant holds across all of them.
  test_simulation(CommitJob.new) do |_scenario|
    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

    # Non-idempotent consequences, yet always exactly one row per committed step
    # — never torn (0 or 3), regardless of where the failure was injected.
    assert_equal 2, Thing.count
    # idempotent bodies replayed safely
    assert_equal 2, ChaoticJob.journal_size
  end
end
