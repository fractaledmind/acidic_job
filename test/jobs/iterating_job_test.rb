# frozen_string_literal: true

require "test_helper"

class IteratingJobTest < ActiveJob::TestCase
  test "workflow runs successfully" do
    IteratingJob.perform_later
    perform_all_jobs

    # Performed only the job
    assert_equal 1, performed_jobs.size
    assert_equal 0, enqueued_jobs.size

    # performs primary IO operation once per iteration
    assert_equal 3, ChaoticJob.journal_size
    assert_equal [ 1, 2, 3 ], ChaoticJob::Journal.entries

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    # iterates over 3 item array before succeeding
    assert_equal 5, AcidicJob::Entry.count
    assert_equal(
      [
        %w[do_something started],
        %w[do_something started],
        %w[do_something started],
        %w[do_something started],
        %w[do_something succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # only one context value for the cursor into the enumerable
    assert_equal 1, AcidicJob::Value.count
    assert_equal 3, AcidicJob::Value.find_by(key: :cursor).value
  end

  test "scenario with error before updating cursor" do
    run_scenario(IteratingJob.new, glitch: glitch_before_call("AcidicJob::Context#[]=", :cursor, Integer)) do
      perform_all_jobs

      # Performed the job and its retry
      assert_equal 2, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # performs primary IO operation once per iteration
      assert_equal 3, ChaoticJob.journal_size
      assert_equal [ 1, 2, 3 ], ChaoticJob::Journal.entries

      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # iterates over 3 item array before succeeding
      assert_equal 7, AcidicJob::Entry.count
      assert_equal(
        [
          %w[do_something started],
          %w[do_something errored],
          %w[do_something started],
          %w[do_something started],
          %w[do_something started],
          %w[do_something started],
          %w[do_something succeeded]
        ],
        execution.entries.ordered.pluck(:step, :action)
      )

      # only one context value for the cursor into the enumerable
      assert_equal 1, AcidicJob::Value.count
      assert_equal 3, AcidicJob::Value.find_by(key: :cursor).value
    end
  end

  test_simulation(IteratingJob.new) do |_scenario|
    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

    # performs primary IO operation once per iteration
    assert_equal 3, ChaoticJob.journal_size
    assert_equal [ 1, 2, 3 ], ChaoticJob::Journal.entries
  end
end
