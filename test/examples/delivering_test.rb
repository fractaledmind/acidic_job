# frozen_string_literal: true

require "test_helper"

module Examples
  class DeliveringTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: job_id) do |w|
          w.step :deliver_email
          w.step :deliver_parameterized_email
          w.step :do_something
        end
      end

      def deliver_email
        # enqueue the message for delivery once, and store it.
        # on retries, just fetch it from the context
        ctx.fetch(:email_1) { TestMailer.hello_world.deliver_later }
      end

      def deliver_parameterized_email
        # enqueue the message for delivery once, and store it.
        # on retries, just fetch it from the context
        ctx.fetch(:email_2) { TestMailer.with({ recipient: "me@mail.com" }).hello_world.deliver_later }
      end

      def do_something
        # idempotent because journal logging is idempotent via Set
        # but this means data logged must be identical across executions
        ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # Performed the job and the mail deliveries
      assert_equal 3, performed_jobs.size
      assert_equal 0, enqueued_jobs.size
      assert_equal 1, performed_jobs.count { |job| job["job_class"] == Job.name }
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
      run_scenario(Job.new, glitch: glitch_before_return("#{Job.name}#deliver_email")) do
        perform_all_jobs
      end

      # Performed the job, the retry, and the mail deliveries
      assert_equal 4, performed_jobs.size
      assert_equal 0, enqueued_jobs.size
      assert_equal 2, performed_jobs.count { |job| job["job_class"] == Job.name }
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

    test_simulation(Job.new) do |_scenario|
      assert_only_one_execution_that_it_is_finished_and_each_step_only_succeeds_once

      # Performed the job, the retry, and the mail deliveries
      assert_equal 4, performed_jobs.size
      assert_equal 0, enqueued_jobs.size
      assert_equal 2, performed_jobs.count { |job| job["job_class"] == Job.name }
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
end
