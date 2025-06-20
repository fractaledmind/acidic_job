# frozen_string_literal: true

require "test_helper"

class AcidicJob::BreakagesTest < ActiveJob::TestCase
  class DefaultsError < StandardError; end
  class DiscardableError < StandardError; end
  class BreakingError < StandardError; end

  class Job < ActiveJob::Base
    include AcidicJob::Workflow

    retry_on DefaultsError
    discard_on DiscardableError

    def perform
      execute_workflow(unique_by: arguments) do |w|
        w.step :step_1
        w.step :step_2
        w.step :step_3
      end
    end

    def step_1; ChaoticJob.log_to_journal!; end
    def step_2; ChaoticJob.log_to_journal!; end
    def step_3; ChaoticJob.log_to_journal!; end
  end

  test "define_workflow: error with no job configuration fails job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "define_workflow.acidic_job"
      next if already_raised

      already_raised = true
      raise BreakingError
    end

    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      assert_raises(BreakingError) do
        perform_all_jobs
      end
    end

    assert already_raised
    assert_equal 0, ChaoticJob.journal_size
    assert_equal 0, AcidicJob::Execution.count
    assert_equal 1, events.count
    assert_equal 0, AcidicJob::Entry.count
  end

  test "define_workflow: discarded error fails job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "define_workflow.acidic_job"

      already_raised = true
      raise DiscardableError
    end
    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      perform_all_jobs
    end

    assert already_raised
    assert_equal 0, ChaoticJob.journal_size
    assert_equal 0, AcidicJob::Execution.count
    assert_equal 1, events.count
    assert_equal 0, AcidicJob::Entry.count
  end

  test "define_workflow: retryable error with no resolution fails job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "define_workflow.acidic_job"

      already_raised = true
      raise DefaultsError
    end

    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      assert_raises(DefaultsError) do
        perform_all_jobs
      end
    end

    assert already_raised
    assert_equal 0, ChaoticJob.journal_size
    assert_equal 0, AcidicJob::Execution.count
    assert_equal 5, events.count
    assert_equal 0, AcidicJob::Entry.count
  end

  test "define_workflow: retryable error with resolution eventually performs job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "define_workflow.acidic_job"
      next if already_raised

      already_raised = true
      raise DefaultsError
    end
    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      perform_all_jobs
    end

    assert already_raised
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count
    assert_equal 16, events.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal(
      [
        "define_workflow.acidic_job",
        "define_workflow.acidic_job", # <-- retried
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job"
      ],
      events.map(&:name)
    )
  end

  test "initialize_workflow: retryable error with resolution eventually performs job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "initialize_workflow.acidic_job"
      next if already_raised

      already_raised = true
      raise DefaultsError
    end
    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      perform_all_jobs
    end

    assert already_raised
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count
    assert_equal 17, events.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal(
      [
        "define_workflow.acidic_job",
        "initialize_workflow.acidic_job",
        "define_workflow.acidic_job", # <-- retried
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job"
      ],
      events.map(&:name)
    )
  end

  test "record_entry-step_1-started: retryable error with resolution eventually performs job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "record_entry.acidic_job"
      next unless event.payload[:step] == "step_1"
      next unless event.payload[:action] == :started
      next if already_raised

      already_raised = true
      raise DefaultsError
    end
    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      perform_all_jobs
    end

    assert already_raised
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count
    assert_equal 21, events.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 errored],
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal(
      [
        "define_workflow.acidic_job",
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job",
        "define_workflow.acidic_job", # <-- retried
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job"
      ],
      events.map(&:name)
    )
  end

  test "perform_step-step_1: retryable error with resolution eventually performs job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "perform_step.acidic_job"
      next unless event.payload[:does] == "step_1"
      next if already_raised

      already_raised = true
      raise DefaultsError
    end
    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      perform_all_jobs
    end

    assert already_raised
    assert_equal 4, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count
    assert_equal 22, events.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 errored],
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal(
      [
        "define_workflow.acidic_job",
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job",
        "define_workflow.acidic_job", # <-- retried
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job"
      ],
      events.map(&:name)
    )
  end

  test "record_entry-step_1-succeeded: retryable error with resolution eventually performs job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "record_entry.acidic_job"
      next unless event.payload[:step] == "step_1"
      next unless event.payload[:action] == :succeeded
      next if already_raised

      already_raised = true
      raise DefaultsError
    end
    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      perform_all_jobs
    end

    assert already_raised
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count
    assert_equal 20, events.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 7, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_1 errored],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal(
      [
        "define_workflow.acidic_job",
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job",
        "define_workflow.acidic_job", # <-- retried
        "initialize_workflow.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job"
      ],
      events.map(&:name)
    )
  end

  test "process_step-step_1: retryable error with resolution eventually performs job" do
    Job.perform_later

    events = []
    already_raised = false
    callback = lambda do |event|
      events << event.dup

      next unless event.name == "process_step.acidic_job"
      next unless event.payload[:does] == "step_1"
      next if already_raised

      already_raised = true
      raise DefaultsError
    end
    ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
      perform_all_jobs
    end

    assert already_raised
    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count
    assert_equal 18, events.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal(
      [
        "define_workflow.acidic_job",
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job",
        "define_workflow.acidic_job", # <-- retried
        "initialize_workflow.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "record_entry.acidic_job",
        "perform_step.acidic_job",
        "record_entry.acidic_job",
        "process_step.acidic_job",
        "process_workflow.acidic_job"
      ],
      events.map(&:name)
    )
  end
end
