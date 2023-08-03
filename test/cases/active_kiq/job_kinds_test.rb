# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveKiq
    class JobKinds < ActiveSupport::TestCase
      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
        Sidekiq::Queues.clear_all
        Sidekiq.redis(&:flushdb)
      end

      def perform_enqueued_jobs
        yield
        Sidekiq::Worker.drain_all
      end

      # MATRIX OF POSSIBLE KINDS OF JOBS
      # [
      #   ["workflow", "staged", "awaited"],
      #   ["workflow", "staged", "unawaited"],
      #   ["workflow", "unstaged", "awaited"],
      #   ["workflow", "unstaged", "unawaited"],
      #   ["non-workflow", "staged", "awaited"],
      #   ["non-workflow", "staged", "unawaited"],
      #   ["non-workflow", "unstaged", "awaited"],
      #   ["non-workflow", "unstaged", "unawaited"],
      # ]

      test "non-workflow, unstaged, unawaited job successfully performs without `Run` records" do
        class NowJobNonWorkflowUnstagedUnawaited < AcidicJob::ActiveKiq
          def perform
            Performance.performed!
          end
        end

        NowJobNonWorkflowUnstagedUnawaited.perform_now

        assert_equal 0, AcidicJob::Run.count
        assert_equal 1, Performance.performances
      end

      test "non-workflow, unstaged, awaited job is invalid" do
        class AwaitingJob < AcidicJob::ActiveKiq; end

        class JobNonWorkflowUnstagedAwaited < AcidicJob::ActiveKiq
          # :nocov:
          def perform
            Performance.performed!
          end
          # :nocov:
        end

        assert_raises ActiveRecord::RecordInvalid do
          AcidicJob::Run.create!(
            idempotency_key: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
            serialized_job: {
              "job_class" => "JobNonWorkflowUnstagedAwaited",
              "job_id" => "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
              "provider_job_id" => nil,
              "queue_name" => "default",
              "priority" => nil,
              "arguments" => [],
              "executions" => 1,
              "exception_executions" => {},
              "locale" => "en",
              "timezone" => "UTC",
              "enqueued_at" => ""
            },
            job_class: "JobNonWorkflowUnstagedAwaited",
            staged: false,
            last_run_at: Time.current,
            recovery_point: "do_something",
            workflow: {
              "do_something" => { "does" => "do_something", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
            },
            awaited_by: AcidicJob::Run.create!(
              idempotency_key: "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
              serialized_job: {
                "job_class" => "AwaitingJob",
                "job_id" => "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
                "provider_job_id" => nil,
                "queue_name" => "default",
                "priority" => nil,
                "arguments" => [],
                "executions" => 1,
                "exception_executions" => {},
                "locale" => "en",
                "timezone" => "UTC",
                "enqueued_at" => ""
              },
              job_class: "AwaitingJob",
              staged: false,
              last_run_at: Time.current,
              recovery_point: "do_something",
              workflow: {
                "do_something" => { "does" => "do_something", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
              }
            )
          )
        end
      end

      test "non-workflow, staged, unawaited job successfully performs with `Run` record" do
        class NowJobNonWorkflowStagedUnawaited < AcidicJob::ActiveKiq
          def perform
            Performance.performed!
          end
        end

        perform_enqueued_jobs do
          NowJobNonWorkflowStagedUnawaited.perform_acidicly
        end

        assert_equal 1, AcidicJob::Run.count
        assert_equal 1, Performance.performances

        run = AcidicJob::Run.find_by(job_class: [self.class.name, "NowJobNonWorkflowStagedUnawaited"].join("::"))

        assert_equal "FINISHED", run.recovery_point
        assert_nil run.error_object
        refute_predicate run, :workflow?
        assert_predicate run, :staged?
        refute_predicate run, :awaited?
      end

      test "non-workflow, staged, awaited job successfully perfoms with 2 `Run` records" do
        class JobNonWorkflowStagedAwaited < AcidicJob::ActiveKiq
          def perform
            Performance.performed!
          end
        end

        class JobAwaitingNonWorkflowStagedAwaited < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :await_step, awaits: [JobNonWorkflowStagedAwaited]
            end
          end
        end

        perform_enqueued_jobs do
          JobAwaitingNonWorkflowStagedAwaited.perform_now
        end

        assert_equal 2, AcidicJob::Run.count
        assert_equal 1, Performance.performances

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "JobAwaitingNonWorkflowStagedAwaited"].join("::")
        )

        assert_equal "FINISHED", parent_run.recovery_point
        assert_predicate parent_run, :workflow?
        refute_predicate parent_run, :staged?
        refute_predicate parent_run, :awaited?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name, "JobNonWorkflowStagedAwaited"].join("::"))

        assert_equal "FINISHED", child_run.recovery_point
        refute_predicate child_run, :workflow?
        assert_predicate child_run, :staged?
        assert_predicate child_run, :awaited?
      end

      test "workflow, unstaged, unawaited job successfully performs with `Run` record" do
        class JobWorkflowUnstagedUnawaited < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            Performance.performed!
          end
        end

        JobWorkflowUnstagedUnawaited.perform_now

        assert_equal 1, AcidicJob::Run.count

        run = AcidicJob::Run.find_by(job_class: [self.class.name, "JobWorkflowUnstagedUnawaited"].join("::"))

        assert_equal "FINISHED", run.recovery_point
        assert_nil run.error_object
        assert_predicate run, :workflow?
        refute_predicate run, :staged?
        refute_predicate run, :awaited?

        assert_equal 1, Performance.performances
      end

      test "workflow, unstaged, awaited job is invalid" do
        class JobAwaitingWorkflowUnstagedAwaited < AcidicJob::ActiveKiq; end

        class JobWorkflowUnstagedAwaited < AcidicJob::ActiveKiq
          # :nocov:
          def perform
            Performance.performed!
          end
          # :nocov:
        end

        assert_raises ActiveRecord::RecordInvalid do
          AcidicJob::Run.create!(
            idempotency_key: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
            serialized_job: {
              "job_class" => "JobWorkflowUnstagedAwaited",
              "job_id" => "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
              "provider_job_id" => nil,
              "queue_name" => "default",
              "priority" => nil,
              "arguments" => [],
              "executions" => 1,
              "exception_executions" => {},
              "locale" => "en",
              "timezone" => "UTC",
              "enqueued_at" => ""
            },
            job_class: "JobWorkflowUnstagedAwaited",
            staged: false,
            last_run_at: Time.current,
            recovery_point: "do_something",
            workflow: {
              "do_something" => { "does" => "do_something", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
            },
            awaited_by: AcidicJob::Run.create!(
              idempotency_key: "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
              serialized_job: {
                "job_class" => "JobAwaitingWorkflowUnstagedAwaited",
                "job_id" => "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
                "provider_job_id" => nil,
                "queue_name" => "default",
                "priority" => nil,
                "arguments" => [],
                "executions" => 1,
                "exception_executions" => {},
                "locale" => "en",
                "timezone" => "UTC",
                "enqueued_at" => ""
              },
              job_class: "JobAwaitingWorkflowUnstagedAwaited",
              staged: false,
              last_run_at: Time.current,
              recovery_point: "do_something",
              workflow: {
                "do_something" => { "does" => "do_something", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
              }
            )
          )
        end
      end

      test "workflow, staged, unawaited job successfully performs with `Run` record" do
        class JobWorkflowStagedUnawaited < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            Performance.performed!
          end
        end

        perform_enqueued_jobs do
          JobWorkflowStagedUnawaited.perform_acidicly
        end

        assert_equal 1, AcidicJob::Run.count

        run = AcidicJob::Run.find_by(job_class: [self.class.name, "JobWorkflowStagedUnawaited"].join("::"))

        assert_equal "FINISHED", run.recovery_point
        assert_nil run.error_object
        assert_predicate run, :workflow?
        assert_predicate run, :staged?
        refute_predicate run, :awaited?

        assert_equal 1, Performance.performances
      end

      test "workflow, staged, awaited job successfully perfoms with 2 `Run` records" do
        class JobWorkflowStagedAwaited < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            Performance.performed!
          end
        end

        class JobAwaitingWorkflowStagedAwaited < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :await_step, awaits: [JobWorkflowStagedAwaited]
            end
          end
        end

        perform_enqueued_jobs do
          JobAwaitingWorkflowStagedAwaited.perform_now
        end

        assert_equal 2, AcidicJob::Run.count
        assert_equal 1, Performance.performances

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "JobAwaitingWorkflowStagedAwaited"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_predicate parent_run, :workflow?
        refute_predicate parent_run, :staged?
        refute_predicate parent_run, :awaited?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name, "JobWorkflowStagedAwaited"].join("::"))

        assert_equal "FINISHED", child_run.recovery_point
        assert_predicate child_run, :workflow?
        assert_predicate child_run, :staged?
        assert_predicate child_run, :awaited?
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
