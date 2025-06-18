# frozen_string_literal: true

require "test_helper"

class DeliveringJobTest < ActiveJob::TestCase
  test "workflow runs successfully" do
    DeliveringJob.perform_later
    perform_all_jobs

    # Performed the job and the mail deliveries
    assert_equal 3, performed_jobs.size
    assert_equal 0, enqueued_jobs.size
    assert_equal 1, performed_jobs.count { |job| job["job_class"] == DeliveringJob.name }
    assert_equal 2, performed_jobs.count { |job| job["job_class"] == "ActionMailer::MailDeliveryJob" }
    assert_equal 1, performed_jobs.count { |job|
      job["arguments"].last&.fetch("_aj_ruby2_keywords") == ["args"]
    }
    assert_equal 1, performed_jobs.count { |job|
      job["arguments"].last&.fetch("_aj_ruby2_keywords") == %w[params args]
    }

    # only performs primary IO operations once per job
    assert_equal 1, ChaoticJob.journal_size

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    # simple walkthrough of the execution
    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[deliver_email started],
        %w[deliver_email succeeded],
        %w[deliver_parameterized_email started],
        %w[deliver_parameterized_email succeeded],
        %w[do_something started],
        %w[do_something succeeded],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # context for each email delivery stored
    assert_equal 2, AcidicJob::Value.count
    email_1 = AcidicJob::Value.find_by(key: :email_1).value
    assert_equal ActionMailer::MailDeliveryJob, email_1.class
    assert_equal(
      ["TestMailer", "hello_world", "deliver_now", { args: [] }],
      email_1.arguments
    )
    email_2 = AcidicJob::Value.find_by(key: :email_2).value
    assert_equal ActionMailer::MailDeliveryJob, email_2.class
    assert_equal(
      ["TestMailer", "hello_world", "deliver_now", { params: { recipient: "me@mail.com" }, args: [] }],
      email_2.arguments
    )
  end

  test "scenario with error before deliver_email returns" do
    run_scenario(DeliveringJob.new, glitch: glitch_before_return("#{DeliveringJob.name}#deliver_email")) do
      perform_all_jobs
    end

    # Performed the job, the retry, and the mail deliveries
    assert_equal 4, performed_jobs.size
    assert_equal 0, enqueued_jobs.size
    assert_equal 2, performed_jobs.count { |job| job["job_class"] == DeliveringJob.name }
    assert_equal 2, performed_jobs.count { |job| job["job_class"] == "ActionMailer::MailDeliveryJob" }
    assert_equal 1, performed_jobs.count { |job|
      job["arguments"].last&.fetch("_aj_ruby2_keywords") == ["args"]
    }
    assert_equal 1, performed_jobs.count { |job|
      job["arguments"].last&.fetch("_aj_ruby2_keywords") == %w[params args]
    }

    # only performs primary IO operations once per job
    assert_equal 1, ChaoticJob.journal_size

    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once
    execution = AcidicJob::Execution.first

    # simple walkthrough of the execution
    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [
        %w[deliver_email started],
        %w[deliver_email errored],
        %w[deliver_email started],
        %w[deliver_email succeeded],
        %w[deliver_parameterized_email started],
        %w[deliver_parameterized_email succeeded],
        %w[do_something started],
        %w[do_something succeeded],
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    # context for each email delivery stored
    assert_equal 2, AcidicJob::Value.count
    email_1 = AcidicJob::Value.find_by(key: :email_1).value
    assert_equal ActionMailer::MailDeliveryJob, email_1.class
    assert_equal(
      ["TestMailer", "hello_world", "deliver_now", { args: [] }],
      email_1.arguments
    )
    email_2 = AcidicJob::Value.find_by(key: :email_2).value
    assert_equal ActionMailer::MailDeliveryJob, email_2.class
    assert_equal(
      ["TestMailer", "hello_world", "deliver_now", { params: { recipient: "me@mail.com" }, args: [] }],
      email_2.arguments
    )
  end

  test_simulation(DeliveringJob.new) do |_scenario|
    assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

    # Performed the job, the retry, and the mail deliveries
    assert_equal 4, performed_jobs.size
    assert_equal 0, enqueued_jobs.size
    assert_equal 2, performed_jobs.count { |job| job["job_class"] == DeliveringJob.name }
    assert_equal 2, performed_jobs.count { |job| job["job_class"] == "ActionMailer::MailDeliveryJob" }
    assert_equal 1, performed_jobs.count { |job|
      job["arguments"].last&.fetch("_aj_ruby2_keywords") == ["args"]
    }
    assert_equal 1, performed_jobs.count { |job|
      job["arguments"].last&.fetch("_aj_ruby2_keywords") == %w[params args]
    }

    # only performs primary IO operations once per job
    assert_equal 1, ChaoticJob.journal_size
  end
end
