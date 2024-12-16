# frozen_string_literal: true

require "test_helper"

class TestMailer < ActionMailer::Base
  def hello_world
    @message = "Hello, world"

    mail from: "test@example.com", to: "user@example.com" do |format|
      format.html { render inline: "<h1><%= @message %></h1>" }
      format.text { render inline: "<%= @message %>" }
    end
  end
end

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
        TestMailer.hello_world.deliver_later
      end

      def deliver_parameterized_email
        TestMailer.with({}).hello_world.deliver_later
      end

      def do_something
        ChaoticJob.log_to_journal!(serialize)
      end
    end

    test "workflow runs successfully" do
      Job.perform_later
      perform_all_jobs

      # Performed the job and the mail deliveries
      assert_equal 3, performed_jobs.size
      assert_equal 0, enqueued_jobs.size

      # only performs primary IO operations once per job
      assert_equal 1, ChaoticJob.journal_size
      assert_equal 2, performed_jobs.select { |job| job["job_class"] == "ActionMailer::MailDeliveryJob" }.size
      assert_equal 1, performed_jobs.select { |job|
        job["arguments"].last&.fetch("_aj_ruby2_keywords") == ["args"]
      }.size
      assert_equal 1, performed_jobs.select { |job|
        job["arguments"].last&.fetch("_aj_ruby2_keywords") == %w[params args]
      }.size

      assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once
      execution = AcidicJob::Execution.first

      # simple walkthrough of the execution
      assert_equal 6, AcidicJob::Entry.count
      assert_equal(
        [%w[deliver_email started],
         %w[deliver_email succeeded],
         %w[deliver_parameterized_email started],
         %w[deliver_parameterized_email succeeded],
         %w[do_something started],
         %w[do_something succeeded]],
        execution.entries.order(timestamp: :asc).pluck(:step, :action)
      )

      # no context needed or stored
      assert_equal 0, AcidicJob::Value.count
    end

    test "simulation" do
      run_simulation(Job.new) do |_scenario|
        assert_only_one_execution_that_is_finished_and_each_step_only_succeeds_once

        # only performs primary IO operations once per job
        assert_equal 1, ChaoticJob.journal_size
        assert_equal 2, performed_jobs.select { |job| job["job_class"] == "ActionMailer::MailDeliveryJob" }.size
        assert_equal 1, performed_jobs.select { |job|
          job["arguments"].last&.fetch("_aj_ruby2_keywords") == ["args"]
        }.size
        assert_equal 1, performed_jobs.select { |job|
          job["arguments"].last&.fetch("_aj_ruby2_keywords") == %w[params args]
        }.size
      end
    end
  end
end
