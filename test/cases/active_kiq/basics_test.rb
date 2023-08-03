# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveKiq
    class Basics < ActiveSupport::TestCase
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

      test "calling `with_acidic_workflow` with `persisting` serializes and saves the hash to the `Run` record" do
        class PersistableValue < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow persisting: { key: :value } do |workflow|
              workflow.step :do_something
            end
          end

          def do_something; end
        end

        result = PersistableValue.perform_now

        assert(result)
        run = AcidicJob::Run.find_by(job_class: [self.class.name, "PersistableValue"].join("::"))

        assert_equal({ "key" => :value }, run.attr_accessors)
      end

      test "basic one step workflow runs successfully" do
        class SucOneStep < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            Performance.performed!
          end
        end

        result = SucOneStep.perform_now

        assert result
        assert_equal 1, Performance.performances
      end

      test "an error raised in a step method is stored in the run record" do
        class ErrOneStep < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            raise CustomErrorForTesting
          end
        end

        assert_raises CustomErrorForTesting do
          ErrOneStep.perform_now
        end

        run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrOneStep"].join("::"))

        assert_instance_of CustomErrorForTesting, run.error_object
      end

      test "basic two step workflow runs successfully" do
        class SucTwoSteps < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :step_one
              workflow.step :step_two
            end
          end

          def step_one
            Performance.performed!
          end

          def step_two
            Performance.performed!
          end
        end

        result = SucTwoSteps.perform_now

        assert result
        assert_equal 2, Performance.performances
      end

      test "basic two step workflow can short-circuit execution via `safely_finish_acidic_job`" do
        class ShortCircuitTwoSteps < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :step_one
              workflow.step :step_two
            end
          end

          def step_one
            Performance.performed!
            safely_finish_acidic_job
          end

          # :nocov:
          def step_two
            Performance.performed!
          end
          # :nocov:
        end

        result = ShortCircuitTwoSteps.perform_now

        assert result
        assert_equal 1, Performance.performances
      end

      test "basic two step workflow can be started from second step if pre-existing run record present" do
        class RestartedTwoSteps < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :step_one
              workflow.step :step_two
            end
          end

          # :nocov:
          def step_one
            Performance.performed!
          end
          # :nocov:

          def step_two
            Performance.performed!
          end
        end

        run = AcidicJob::Run.create!(
          idempotency_key: "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
          serialized_job: {
            "job_class" => "RestartedTwoSteps",
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
          job_class: "RestartedTwoSteps",
          last_run_at: Time.current,
          recovery_point: "step_two",
          workflow: {
            "step_one" => { "does" => "step_one", "awaits" => [], "for_each" => nil, "then" => "step_two" },
            "step_two" => { "does" => "step_two", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
          }
        )
        AcidicJob::Run.stub(:find_by, ->(*) { run }) do
          result = RestartedTwoSteps.perform_now

          assert result
        end
        assert_equal 1, Performance.performances
      end

      test "error in first step rolls back step transaction" do
        class ErrorInStepMethod < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow persisting: { accessor: nil } do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            self.accessor = "value"
            raise CustomErrorForTesting
          end
        end

        assert_raises CustomErrorForTesting do
          ErrorInStepMethod.perform_now
        end

        assert_equal(1, AcidicJob::Run.count)
        run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrorInStepMethod"].join("::"))

        assert_equal run.error_object.class, CustomErrorForTesting
        assert_equal({ "accessor" => nil }, run.attr_accessors)
      end

      test "logic inside `with_acidic_workflow` block is executed appropriately" do
        class SwitchOnStep < AcidicJob::ActiveKiq
          def perform(bool)
            with_acidic_workflow do |workflow|
              workflow.step :do_something if bool
            end
          end

          def do_something
            raise CustomErrorForTesting
          end
        end

        assert_raises CustomErrorForTesting do
          SwitchOnStep.perform_now(true)
        end

        assert_raises AcidicJob::NoDefinedSteps do
          SwitchOnStep.perform_now(false)
        end

        assert_equal 1, AcidicJob::Run.count
      end

      test "finished run immediately returns when processed" do
        class AlreadyFinished < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :step_one
            end
          end

          # :nocov:
          def step_one
            Performance.performed!
          end
          # :nocov:
        end

        run = AcidicJob::Run.create!(
          idempotency_key: "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
          serialized_job: {
            "job_class" => "AlreadyFinished",
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
          job_class: "ErrUnknownRecoveryPoint",
          last_run_at: Time.current,
          recovery_point: "FINISHED",
          workflow: {
            "step_one" => { "does" => "step_one", "awaits" => [], "for_each" => nil, "then" => "step_two" },
            "step_two" => { "does" => "step_two", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
          }
        )
        AcidicJob::Run.stub(:find_by, ->(*) { run }) do
          result = AlreadyFinished.perform_now

          assert result
        end
        assert_equal 0, Performance.performances
      end

      test "`with_acidic_workflow` always returns boolean, regardless of last value of the block" do
        class ArbitraryReturnValue < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something
              12_345
            end
          end

          def do_something
            Performance.performed!
          end
        end

        result = ArbitraryReturnValue.perform_now

        assert result
        assert_equal 1, Performance.performances
      end

      test "can persist ActiveRecord model instance in attributes" do
        class RecordPersisting < AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow persisting: { notice: nil } do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            self.notice = Notification.create!(recipient_id: 1, recipient_type: "User")
            Performance.performed!
          end
        end

        perform_enqueued_jobs do
          RecordPersisting.perform_now
        end

        assert_equal 1, AcidicJob::Run.count
        assert_equal 1, Performance.performances

        run = AcidicJob::Run.find_by(job_class: [self.class.name, "RecordPersisting"].join("::"))

        assert_equal "FINISHED", run.recovery_point
        assert_equal 1, Notification.count
      end

      test "job that inherits from AcidicJob::ActiveKiq is a known job" do
        class AcidicInheritsJob < ::AcidicJob::ActiveKiq
          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            Performance.performed!
          end
        end

        result = AcidicInheritsJob.perform_now

        assert result
        assert_equal 1, Performance.performances
      end

      test "job that mixes in AcidicJob::Mixin is an unknown job" do
        class AcidicMixesJob
          include ::Sidekiq::Worker
          include ::Sidekiq::JobUtil
          include ::ActiveSupport::Callbacks
          define_callbacks :perform
          include ::AcidicJob::Mixin

          def perform
            with_acidic_workflow do |workflow|
              workflow.step :do_something
            end
          end

          def do_something
            Performance.performed!
          end
        end

        assert_raises AcidicJob::UnknownJobAdapter do
          AcidicMixesJob.new.perform
        end
      end

      test "configured job can be performed acidicly" do
        class ConfigurableJob < ::AcidicJob::ActiveKiq
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
          ConfigurableJob.set(priority: 10).perform_acidicly
        end

        assert_equal 1, AcidicJob::Run.count

        run = AcidicJob::Run.find_by(job_class: [self.class.name, "ConfigurableJob"].join("::"))

        assert_equal "FINISHED", run.recovery_point
        assert_equal 1, Performance.performances
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
