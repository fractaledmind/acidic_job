# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
class TestCases < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def before_setup
    super()
    AcidicJob::Run.delete_all
    Notification.delete_all
    Performance.reset!
  end

  test "`AcidicJob::Base` only adds a few methods to job" do
    class BareJob < AcidicJob::Base; end

    expected_methods = %i[
      _run_finish_callbacks
      _finish_callbacks
      with_acidic_workflow
      idempotency_key
      safely_finish_acidic_job
      idempotently
      with_acidity
    ].sort
    assert_equal expected_methods,
                 (BareJob.instance_methods - ActiveJob::Base.instance_methods).sort
  end

  test "`AcidicJob::Base` in parent class adds methods to any job that inherit from parent" do
    class ParentJob < AcidicJob::Base; end
    class ChildJob < ParentJob; end

    expected_methods = %i[
      _run_finish_callbacks
      _finish_callbacks
      with_acidic_workflow
      idempotency_key
      safely_finish_acidic_job
      idempotently
      with_acidity
    ].sort
    assert_equal expected_methods,
                 (ChildJob.instance_methods - ActiveJob::Base.instance_methods).sort
  end

  test "calling `with_acidic_workflow` without a block raises `MissingWorkflowBlock`" do
    class WithoutBlock < AcidicJob::Base
      def perform
        with_acidic_workflow
      end
    end

    assert_raises AcidicJob::MissingWorkflowBlock do
      WithoutBlock.perform_now
    end
  end

  test "calling `with_acidic_workflow` with a block without steps raises `NoDefinedSteps`" do
    class WithoutSteps < AcidicJob::Base
      def perform
        with_acidic_workflow {} # rubocop:disable Lint/EmptyBlock
      end
    end

    assert_raises AcidicJob::NoDefinedSteps do
      WithoutSteps.perform_now
    end
  end

  test "calling `with_acidic_workflow` twice raises `RedefiningWorkflow`" do
    class DoubleWorkflow < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end

        with_acidic_workflow {} # rubocop:disable Lint/EmptyBlock
      end

      def do_something; end
    end

    assert_raises AcidicJob::RedefiningWorkflow do
      DoubleWorkflow.perform_now
    end
  end

  test "calling `with_acidic_workflow` with an undefined step method without `awaits` raises `UndefinedStepMethod`" do
    class UndefinedStep < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :no_op
        end
      end
    end

    assert_raises AcidicJob::UndefinedStepMethod do
      UndefinedStep.perform_now
    end
  end

  test "calling `with_acidic_workflow` with `persisting` unserializable value throws `UnserializableValue` error" do
    class UnpersistableValue < AcidicJob::Base
      def perform
        with_acidic_workflow persisting: { key: -> { :some_proc } } do |workflow|
          workflow.step :do_something
        end
      end

      def do_something; end
    end

    assert_raises AcidicJob::UnserializableValue do
      UnpersistableValue.perform_now
    end
  end

  test "calling `with_acidic_workflow` with `persisting` an attribute with a pre-defined reader is handled smoothly" do
    class PersistingAttrReader < AcidicJob::Base
      attr_reader :attr

      def perform
        with_acidic_workflow persisting: { attr: nil } do |workflow|
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    PersistingAttrReader.perform_now

    run = AcidicJob::Run.find_by(job_class: "TestCases::PersistingAttrReader")
    assert_equal "FINISHED", run.recovery_point
    assert_nil run.error_object

    assert_equal 1, Performance.performances
  end

  test "step method that takes an argument throws `TooManyParametersForStepMethod` error" do
    class StepMethodTakesArg < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      end

      def do_something(_arg); end
    end

    assert_raises AcidicJob::TooManyParametersForStepMethod do
      StepMethodTakesArg.perform_now
    end
  end

  test "calling `with_acidic_workflow` with `persisting` serializes and saves the hash to the `Run` record" do
    class PersistableValue < AcidicJob::Base
      def perform
        with_acidic_workflow persisting: { key: :value } do |workflow|
          workflow.step :do_something
        end
      end

      def do_something; end
    end

    result = PersistableValue.perform_now
    assert_equal result, true
    run = AcidicJob::Run.find_by(job_class: "TestCases::PersistableValue")
    assert_equal run.attr_accessors, { "key" => :value }
  end

  test "calling `idempotency_key` when `acidic_identifier` is unconfigured returns `job_id`" do
    class WithoutAcidicIdentifier < AcidicJob::Base
      def perform; end
    end

    job = WithoutAcidicIdentifier.new
    assert_equal job.job_id, job.idempotency_key
  end

  test "calling `idempotency_key` when `acidic_by_job_identifier` is set returns `job_id`" do
    class AcidicByIdentifier < AcidicJob::Base
      acidic_by_job_identifier

      def perform; end
    end

    job = AcidicByIdentifier.new
    assert_equal job.job_id, job.idempotency_key
  end

  test "calling `idempotency_key` when `acidic_by_job_arguments` is set returns hexidigest" do
    class AcidicByArguments < AcidicJob::Base
      acidic_by_job_arguments

      def perform; end
    end

    job = AcidicByArguments.new
    assert_equal "385eae75214ec6df219f20e618c5dff7b4c56943", job.idempotency_key
  end

  test "calling `idempotency_key` when `acidic_by` is a block returning string returns hexidigest" do
    class AcidicByProcWithString < AcidicJob::Base
      acidic_by do
        "a"
      end

      def perform; end
    end

    job = AcidicByProcWithString.new
    assert_equal "caf96a62bddefea002b6bab33b6058ec415f45ca", job.idempotency_key
  end

  test "calling `idempotency_key` when `acidic_by` is a block returning array of strings returns hexidigest" do
    class AcidicByProcWithArrayOfStrings < AcidicJob::Base
      acidic_by do
        %w[a b]
      end

      def perform; end
    end

    job = AcidicByProcWithArrayOfStrings.new
    assert_equal "6d4d8c572ea735cc0ae6fbf3041253f3dc16d9ee", job.idempotency_key
  end

  test "invalid worker throws `UnknownJobAdapter` error" do
    assert_raises AcidicJob::UnknownJobAdapter do
      Class.new do
        include AcidicJob::Mixin
      end
    end
  end

  test "unknown `awaits` method throws `UnknownAwaitedJob` error" do
    class ErrAwaitsUnknown < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: :undefined_method
          workflow.step :do_something
        end
      end

      # :nocov:
      def do_something
        Performance.performed!
      end
      # :nocov:
    end

    assert_raises AcidicJob::UnknownAwaitedJob do
      ErrAwaitsUnknown.perform_now
    end

    assert_equal 0, Performance.performances
  end

  test "invalid `awaits` value throws `UnknownAwaitedJob` error" do
    class ErrAwaitsInvalid < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: 123
          workflow.step :do_something
        end
      end

      # :nocov:
      def do_something
        Performance.performed!
      end
      # :nocov:
    end

    assert_raises AcidicJob::UnknownAwaitedJob do
      ErrAwaitsInvalid.perform_now
    end

    assert_equal 0, Performance.performances
  end

  test "nil `awaits` value is ignored and workflow continues" do
    class ErrAwaitsNil < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [nil]
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    ErrAwaitsNil.perform_now

    assert_equal 1, Performance.performances
  end

  test "invalid workflow in run record raises `UnknownRecoveryPoint`" do
    class InvalidWorkflowRun < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      end

      # :nocov:
      def do_something
        Performance.performed!
      end
      # :nocov:
    end

    run = AcidicJob::Run.create!(
      idempotency_key: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
      serialized_job: {
        "job_class" => "TestCases::InvalidWorkflowRun",
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
      job_class: "TestCases::InvalidWorkflowRun",
      staged: false,
      last_run_at: Time.current,
      recovery_point: "OLD_RECOVERY_POINT_FROM_BEFORE_A_NEW_RELEASE",
      workflow: {
        "do_something" => { "does" => "do_something", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
      }
    )
    AcidicJob::Run.stub(:find_by, ->(*) { run }) do
      assert_raises AcidicJob::UnknownRecoveryPoint do
        InvalidWorkflowRun.perform_now
      end
    end
    assert_equal 0, Performance.performances
  end

  test "basic one step workflow runs successfully" do
    class SucOneStep < AcidicJob::Base
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
    assert_equal true, result
    assert_equal 1, Performance.performances
  end

  test "an error raised in a step method is stored in the run record" do
    class ErrOneStep < AcidicJob::Base
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

    run = AcidicJob::Run.find_by(job_class: "TestCases::ErrOneStep")
    assert_equal CustomErrorForTesting, run.error_object.class
  end

  test "basic two step workflow runs successfully" do
    class SucTwoSteps < AcidicJob::Base
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
    assert_equal true, result
    assert_equal 2, Performance.performances
  end

  test "basic two step workflow can short-circuit execution via `safely_finish_acidic_job`" do
    class ShortCircuitTwoSteps < AcidicJob::Base
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
    assert_equal true, result
    assert_equal 1, Performance.performances
  end

  test "basic two step workflow can be started from second step if pre-existing run record present" do
    class RestartedTwoSteps < AcidicJob::Base
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
        "job_class" => "TestCases::RestartedTwoSteps",
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
      job_class: "TestCases::RestartedTwoSteps",
      last_run_at: Time.current,
      recovery_point: "step_two",
      workflow: {
        "step_one" => { "does" => "step_one", "awaits" => [], "for_each" => nil, "then" => "step_two" },
        "step_two" => { "does" => "step_two", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
      }
    )
    AcidicJob::Run.stub(:find_by, ->(*) { run }) do
      result = RestartedTwoSteps.perform_now
      assert_equal true, result
    end
    assert_equal 1, Performance.performances
  end

  test "passing `for_each` option not in `providing` hash throws `UnknownForEachCollection` error" do
    class UnknownForEachStep < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something, for_each: :unknown_collection
        end
      end

      def do_something(item); end
    end

    assert_raises AcidicJob::UnknownForEachCollection do
      UnknownForEachStep.perform_now
    end
  end

  test "passing `for_each` option that isn't iterable throws `UniterableForEachCollection` error" do
    class UniterableForEachStep < AcidicJob::Base
      def perform
        with_acidic_workflow persisting: { collection: true } do |workflow|
          workflow.step :do_something, for_each: :collection
        end
      end

      def do_something(item); end
    end

    assert_raises AcidicJob::UniterableForEachCollection do
      UniterableForEachStep.perform_now
    end
  end

  test "passing valid `for_each` option iterates over collection with step method" do
    class ValidForEachStep < AcidicJob::Base
      attr_reader :processed_items

      def initialize
        @processed_items = []
        super()
      end

      def perform
        with_acidic_workflow persisting: { collection: (1..5) } do |workflow|
          workflow.step :do_something, for_each: :collection
        end
      end

      def do_something(item)
        @processed_items << item
      end
    end

    job = ValidForEachStep.new
    job.perform_now
    assert_equal [1, 2, 3, 4, 5], job.processed_items
  end

  test "can pass same `for_each` option to multiple step methods" do
    class MultipleForEachSteps < AcidicJob::Base
      attr_reader :step_one_processed_items, :step_two_processed_items

      def initialize
        @step_one_processed_items = []
        @step_two_processed_items = []
        super()
      end

      def perform
        with_acidic_workflow persisting: { items: (1..5) } do |workflow|
          workflow.step :step_one, for_each: :items
          workflow.step :step_two, for_each: :items
        end
      end

      def step_one(item)
        @step_one_processed_items << item
      end

      def step_two(item)
        @step_two_processed_items << item
      end
    end

    job = MultipleForEachSteps.new
    job.perform_now
    assert_equal [1, 2, 3, 4, 5], job.step_one_processed_items
    assert_equal [1, 2, 3, 4, 5], job.step_two_processed_items
  end

  test "can define `after_finish` callbacks" do
    class AfterFinishCallback < AcidicJob::Base
      set_callback :finish, :after, :delete_run_record

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      end

      def do_something; end

      def delete_run_record
        @acidic_job_run.destroy!
      end
    end

    result = AfterFinishCallback.perform_now
    assert_equal true, result
    assert_equal 0, AcidicJob::Run.count
  end

  test "`after_finish` callbacks don't run if job errors" do
    class ErrAfterFinishCallback < AcidicJob::Base
      set_callback :finish, :after, :delete_run_record

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      end

      def do_something
        raise CustomErrorForTesting
      end

      # :nocov:
      def delete_run_record
        @acidic_job_run.destroy!
      end
      # :nocov:
    end

    assert_raises CustomErrorForTesting do
      ErrAfterFinishCallback.perform_now
    end
    assert_equal 1, AcidicJob::Run.count
    assert_equal 1, AcidicJob::Run.where(job_class: "TestCases::ErrAfterFinishCallback").count
  end

  test "rescued error in `perform` doesn't prevent `Run#error_object` from being stored" do
    class ErrorAndRescueInPerform < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      rescue CustomErrorForTesting
        true
      end

      def do_something
        raise CustomErrorForTesting
      end
    end

    result = ErrorAndRescueInPerform.perform_now
    assert_equal result, true
    assert_equal 1, AcidicJob::Run.count
    run = AcidicJob::Run.find_by(job_class: "TestCases::ErrorAndRescueInPerform")
    assert_equal CustomErrorForTesting, run.error_object.class
  end

  test "error in first step rolls back step transaction" do
    class ErrorInStepMethod < AcidicJob::Base
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

    assert_equal AcidicJob::Run.count, 1
    run = AcidicJob::Run.find_by(job_class: "TestCases::ErrorInStepMethod")
    assert_equal run.error_object.class, CustomErrorForTesting
    assert_equal({ "accessor" => nil }, run.attr_accessors)
  end

  test "logic inside `with_acidic_workflow` block is executed appropriately" do
    class SwitchOnStep < AcidicJob::Base
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

  test "run with unknown `recovery_point` value throws `UnknownRecoveryPoint` error when processed" do
    class ErrUnknownRecoveryPoint < AcidicJob::Base
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
        "job_class" => "TestCases::ErrUnknownRecoveryPoint",
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
      job_class: "TestCases::ErrUnknownRecoveryPoint",
      last_run_at: Time.current,
      recovery_point: "unknown_step",
      workflow: {
        "step_one" => { "does" => "step_one", "awaits" => [], "for_each" => nil, "then" => "step_two" },
        "step_two" => { "does" => "step_two", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
      }
    )
    AcidicJob::Run.stub(:find_by, ->(*) { run }) do
      assert_raises AcidicJob::UnknownRecoveryPoint do
        ErrUnknownRecoveryPoint.perform_now
      end
    end
    assert_equal 0, Performance.performances
  end

  test "finished run immediately returns when processed" do
    class AlreadyFinished < AcidicJob::Base
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
        "job_class" => "TestCases::AlreadyFinished",
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
      job_class: "TestCases::ErrUnknownRecoveryPoint",
      last_run_at: Time.current,
      recovery_point: "FINISHED",
      workflow: {
        "step_one" => { "does" => "step_one", "awaits" => [], "for_each" => nil, "then" => "step_two" },
        "step_two" => { "does" => "step_two", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
      }
    )
    AcidicJob::Run.stub(:find_by, ->(*) { run }) do
      result = AlreadyFinished.perform_now
      assert_equal true, result
    end
    assert_equal 0, Performance.performances
  end

  test "`with_acidic_workflow` always returns boolean, regardless of last value of the block" do
    class ArbitraryReturnValue < AcidicJob::Base
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
    assert_equal true, result
    assert_equal 1, Performance.performances
  end

  test "staged workflow job only creates one `AcidicJob::Run` record" do
    class StagedWorkflowJob < AcidicJob::Base
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
      StagedWorkflowJob.perform_acidicly
    end

    assert_equal 1, AcidicJob::Run.count

    run = AcidicJob::Run.find_by(job_class: "TestCases::StagedWorkflowJob")
    assert_equal "FINISHED", run.recovery_point
    assert_equal 1, Performance.performances
  end

  test "workflow job with successful `awaits` job runs successfully" do
    class SimpleWorkflowJob < AcidicJob::Base
      class SucAsyncJob < AcidicJob::Base
        def perform
          Performance.performed!
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [SucAsyncJob]
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    perform_enqueued_jobs do
      SimpleWorkflowJob.perform_later
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::SimpleWorkflowJob")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::SimpleWorkflowJob::SucAsyncJob")
    assert_equal "FINISHED", child_run.recovery_point
    assert_equal true, child_run.staged?

    assert_equal 2, Performance.performances
  end

  test "workflow job with erroring `awaits` job does not progress and does not store error object" do
    class WorkflowWithErrAwaitsJob < AcidicJob::Base
      class ErrAsyncJob < AcidicJob::Base
        def perform
          raise CustomErrorForTesting
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [ErrAsyncJob]
          workflow.step :do_something
        end
      end

      # :nocov:
      def do_something
        Performance.performed!
      end
      # :nocov:
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        WorkflowWithErrAwaitsJob.perform_later
      end
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::WorkflowWithErrAwaitsJob")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::WorkflowWithErrAwaitsJob::ErrAsyncJob")
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 0, Performance.performances
  end

  test "workflow job with successful awaits job that itself awaits another successful job" do
    class NestedSucAwaitSteps < AcidicJob::Base
      class SucAwaitedAndAwaits < AcidicJob::Base
        class NestedSucAwaited < AcidicJob::Base
          def perform
            Performance.performed!
          end
        end

        def perform
          with_acidic_workflow do |workflow|
            workflow.step :await_nested_step, awaits: [NestedSucAwaited]
          end
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [SucAwaitedAndAwaits]
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    perform_enqueued_jobs do
      NestedSucAwaitSteps.perform_later
    end

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::NestedSucAwaitSteps")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::NestedSucAwaitSteps::SucAwaitedAndAwaits"
    )
    assert_equal "FINISHED", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    grandchild_run = AcidicJob::Run.find_by(
      job_class: "TestCases::NestedSucAwaitSteps::SucAwaitedAndAwaits::NestedSucAwaited"
    )
    assert_equal "FINISHED", grandchild_run.recovery_point
    assert_nil grandchild_run.error_object
    assert_equal true, grandchild_run.staged?

    assert_equal 2, Performance.performances
  end

  test "workflow job with successful `awaits` job that itself `awaits` another erroring job" do
    class NestedErrAwaitSteps < AcidicJob::Base
      class SucAwaitedAndAwaitsJob < AcidicJob::Base
        class NestedErrAwaitedJob < AcidicJob::Base
          def perform
            raise CustomErrorForTesting
          end
        end

        def perform
          with_acidic_workflow do |workflow|
            workflow.step :await_nested_step, awaits: [NestedErrAwaitedJob]
          end
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [SucAwaitedAndAwaitsJob]
          workflow.step :do_something
        end
      end

      # :nocov:
      def do_something
        Performance.performed!
      end
      # :nocov:
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        NestedErrAwaitSteps.perform_later
      end
    end

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::NestedErrAwaitSteps")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::NestedErrAwaitSteps::SucAwaitedAndAwaitsJob"
    )
    assert_equal "await_nested_step", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    grandchild_run = AcidicJob::Run.find_by(
      job_class: "TestCases::NestedErrAwaitSteps::SucAwaitedAndAwaitsJob::NestedErrAwaitedJob"
    )
    assert_nil grandchild_run.recovery_point
    assert_nil grandchild_run.error_object
    assert_equal true, grandchild_run.staged?

    assert_equal 0, Performance.performances
  end

  test "workflow job with successful awaits initialized with arguments" do
    class SucArgAwaitStep < AcidicJob::Base
      class SucArgJob < AcidicJob::Base
        def perform(_arg)
          Performance.performed!
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [SucArgJob.with(123)]
        end
      end
    end

    perform_enqueued_jobs do
      SucArgAwaitStep.perform_later
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::SucArgAwaitStep")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::SucArgAwaitStep::SucArgJob")
    assert_equal "FINISHED", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 1, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as Symbol that returns successful awaited job class" do
    class SucDynamicAwaitClsAsSym < AcidicJob::Base
      class SucDynamicAwaitFromSymJob < AcidicJob::Base
        def perform
          Performance.performed!
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        [SucDynamicAwaitFromSymJob]
      end
    end

    perform_enqueued_jobs do
      SucDynamicAwaitClsAsSym.perform_later
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::SucDynamicAwaitClsAsSym")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::SucDynamicAwaitClsAsSym::SucDynamicAwaitFromSymJob"
    )
    assert_equal "FINISHED", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 1, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as Symbol that returns successful awaited job instance" do
    class SucDynamicAwaitInstAsSym < AcidicJob::Base
      class SucDynamicAwaitFromSymJob < AcidicJob::Base
        def perform(_arg)
          Performance.performed!
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        [SucDynamicAwaitFromSymJob.with(123)]
      end
    end

    perform_enqueued_jobs do
      SucDynamicAwaitInstAsSym.perform_later
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::SucDynamicAwaitInstAsSym")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::SucDynamicAwaitInstAsSym::SucDynamicAwaitFromSymJob"
    )
    assert_equal "FINISHED", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 1, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as Symbol that returns erroring awaited job class" do
    class ErrDynamicAwaitClsAsSym < AcidicJob::Base
      class ErrDynamicAwaitFromSymJob < AcidicJob::Base
        def perform
          raise CustomErrorForTesting
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        [ErrDynamicAwaitFromSymJob]
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        ErrDynamicAwaitClsAsSym.perform_later
      end
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::ErrDynamicAwaitClsAsSym")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::ErrDynamicAwaitClsAsSym::ErrDynamicAwaitFromSymJob"
    )
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 0, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as Symbol that returns erroring awaited job instance" do
    class ErrDynamicAwaitInstAsSym < AcidicJob::Base
      class ErrDynamicAwaitFromSymJob < AcidicJob::Base
        def perform(_arg)
          raise CustomErrorForTesting
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        [ErrDynamicAwaitFromSymJob.with(123)]
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        ErrDynamicAwaitInstAsSym.perform_later
      end
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::ErrDynamicAwaitInstAsSym")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::ErrDynamicAwaitInstAsSym::ErrDynamicAwaitFromSymJob"
    )
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 0, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as String that returns successful awaited job class" do
    class SucDynamicAwaitClsAsString < AcidicJob::Base
      class SucDynamicAwaitFromStringJob < AcidicJob::Base
        def perform
          Performance.performed!
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        [SucDynamicAwaitFromStringJob]
      end
    end

    perform_enqueued_jobs do
      SucDynamicAwaitClsAsString.perform_later
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::SucDynamicAwaitClsAsString")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::SucDynamicAwaitClsAsString::SucDynamicAwaitFromStringJob"
    )
    assert_equal "FINISHED", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 1, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as String that returns successful awaited job instance" do
    class SucDynamicAwaitInstAsString < AcidicJob::Base
      class SucDynamicAwaitFromStringJob < AcidicJob::Base
        def perform(_arg)
          Performance.performed!
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        [SucDynamicAwaitFromStringJob.with(123)]
      end
    end

    perform_enqueued_jobs do
      SucDynamicAwaitInstAsString.perform_later
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::SucDynamicAwaitInstAsString")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::SucDynamicAwaitInstAsString::SucDynamicAwaitFromStringJob"
    )
    assert_equal "FINISHED", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 1, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as String that returns erroring awaited job class" do
    class ErrDynamicAwaitClsAsString < AcidicJob::Base
      class ErrDynamicAwaitFromStringJob < AcidicJob::Base
        def perform
          raise CustomErrorForTesting
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        [ErrDynamicAwaitFromStringJob]
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        ErrDynamicAwaitClsAsString.perform_later
      end
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::ErrDynamicAwaitClsAsString")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::ErrDynamicAwaitClsAsString::ErrDynamicAwaitFromStringJob"
    )
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 0, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as String that returns erroring awaited job instance" do
    class ErrDynamicAwaitInstAsString < AcidicJob::Base
      class ErrDynamicAwaitFromStringJob < AcidicJob::Base
        def perform(_arg)
          raise CustomErrorForTesting
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        [ErrDynamicAwaitFromStringJob.with(123)]
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        ErrDynamicAwaitInstAsString.perform_later
      end
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::ErrDynamicAwaitInstAsString")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::ErrDynamicAwaitInstAsString::ErrDynamicAwaitFromStringJob"
    )
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 0, Performance.performances
  end

  # -----------------------------------------------------------------------------------------------
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
    class NowJobNonWorkflowUnstagedUnawaited < AcidicJob::Base
      def perform
        Performance.performed!
      end
    end

    NowJobNonWorkflowUnstagedUnawaited.perform_now

    assert_equal 0, AcidicJob::Run.count
    assert_equal 1, Performance.performances
  end

  test "non-workflow, unstaged, awaited job is invalid" do
    class AwaitingJob < AcidicJob::Base; end

    class JobNonWorkflowUnstagedAwaited < AcidicJob::Base
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
          "job_class" => "TestCases::JobNonWorkflowUnstagedAwaited",
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
        job_class: "TestCases::JobNonWorkflowUnstagedAwaited",
        staged: false,
        last_run_at: Time.current,
        recovery_point: "do_something",
        workflow: {
          "do_something" => { "does" => "do_something", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
        },
        awaited_by: AcidicJob::Run.create!(
          idempotency_key: "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
          serialized_job: {
            "job_class" => "TestCases::AwaitingJob",
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
          job_class: "TestCases::AwaitingJob",
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
    class NowJobNonWorkflowStagedUnawaited < AcidicJob::Base
      def perform
        Performance.performed!
      end
    end

    perform_enqueued_jobs do
      NowJobNonWorkflowStagedUnawaited.perform_acidicly
    end

    assert_equal 1, AcidicJob::Run.count
    assert_equal 1, Performance.performances

    run = AcidicJob::Run.find_by(job_class: "TestCases::NowJobNonWorkflowStagedUnawaited")
    assert_equal "FINISHED", run.recovery_point
    assert_nil run.error_object
    assert_equal false, run.workflow?
    assert_equal true, run.staged?
    assert_equal false, run.awaited?
  end

  test "non-workflow, staged, awaited job successfully perfoms with 2 `Run` records" do
    class JobNonWorkflowStagedAwaited < AcidicJob::Base
      def perform
        Performance.performed!
      end
    end

    class JobAwaitingNonWorkflowStagedAwaited < AcidicJob::Base
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

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobAwaitingNonWorkflowStagedAwaited")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_equal true, parent_run.workflow?
    assert_equal false, parent_run.staged?
    assert_equal false, parent_run.awaited?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::JobNonWorkflowStagedAwaited")
    assert_equal "FINISHED", child_run.recovery_point
    assert_equal false, child_run.workflow?
    assert_equal true, child_run.staged?
    assert_equal true, child_run.awaited?
  end

  test "workflow, unstaged, unawaited job successfully performs with `Run` record" do
    class JobWorkflowUnstagedUnawaited < AcidicJob::Base
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

    run = AcidicJob::Run.find_by(job_class: "TestCases::JobWorkflowUnstagedUnawaited")
    assert_equal "FINISHED", run.recovery_point
    assert_nil run.error_object
    assert_equal true, run.workflow?
    assert_equal false, run.staged?
    assert_equal false, run.awaited?

    assert_equal 1, Performance.performances
  end

  test "workflow, unstaged, awaited job is invalid" do
    class JobAwaitingWorkflowUnstagedAwaited < AcidicJob::Base; end

    class JobWorkflowUnstagedAwaited < AcidicJob::Base
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
          "job_class" => "TestCases::JobWorkflowUnstagedAwaited",
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
        job_class: "TestCases::JobWorkflowUnstagedAwaited",
        staged: false,
        last_run_at: Time.current,
        recovery_point: "do_something",
        workflow: {
          "do_something" => { "does" => "do_something", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
        },
        awaited_by: AcidicJob::Run.create!(
          idempotency_key: "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
          serialized_job: {
            "job_class" => "TestCases::JobAwaitingWorkflowUnstagedAwaited",
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
          job_class: "TestCases::JobAwaitingWorkflowUnstagedAwaited",
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
    class JobWorkflowStagedUnawaited < AcidicJob::Base
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

    run = AcidicJob::Run.find_by(job_class: "TestCases::JobWorkflowStagedUnawaited")
    assert_equal "FINISHED", run.recovery_point
    assert_nil run.error_object
    assert_equal true, run.workflow?
    assert_equal true, run.staged?
    assert_equal false, run.awaited?

    assert_equal 1, Performance.performances
  end

  test "workflow, staged, awaited job successfully perfoms with 2 `Run` records" do
    class JobWorkflowStagedAwaited < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    class JobAwaitingWorkflowStagedAwaited < AcidicJob::Base
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

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobAwaitingWorkflowStagedAwaited")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_equal true, parent_run.workflow?
    assert_equal false, parent_run.staged?
    assert_equal false, parent_run.awaited?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::JobWorkflowStagedAwaited")
    assert_equal "FINISHED", child_run.recovery_point
    assert_equal true, child_run.workflow?
    assert_equal true, child_run.staged?
    assert_equal true, child_run.awaited?
  end

  # -----------------------------------------------------------------------------------------------

  test "basic one step workflow awaiting 2 jobs runs successfully" do
    class JobAwaitingTwoJobs < AcidicJob::Base
      class FirstAwaitedJob < AcidicJob::Base
        def perform
          Performance.performed!
        end
      end

      class SecondAwaitedJob < AcidicJob::Base
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

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :no_op, awaits: [FirstAwaitedJob, SecondAwaitedJob]
        end
      end
    end

    perform_enqueued_jobs do
      JobAwaitingTwoJobs.perform_now
    end

    assert_equal 3, AcidicJob::Run.count
    assert_equal 3, Performance.performances

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobAwaitingTwoJobs")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_equal true, parent_run.workflow?
    assert_equal false, parent_run.staged?
    assert_equal false, parent_run.awaited?

    first_child_run = AcidicJob::Run.find_by(job_class: "TestCases::JobAwaitingTwoJobs::FirstAwaitedJob")
    assert_equal "FINISHED", first_child_run.recovery_point
    assert_equal false, first_child_run.workflow?
    assert_equal true, first_child_run.staged?
    assert_equal true, first_child_run.awaited?

    second_child_run = AcidicJob::Run.find_by(job_class: "TestCases::JobAwaitingTwoJobs::SecondAwaitedJob")
    assert_equal "FINISHED", second_child_run.recovery_point
    assert_equal true, second_child_run.workflow?
    assert_equal true, second_child_run.staged?
    assert_equal true, second_child_run.awaited?
  end

  test "nested workflow with all awaited job classes runs successfully" do
    class WithSucGrandChildAwaitCls < AcidicJob::Base
      class WithSucChildAwaitCls < AcidicJob::Base
        class SucJob < AcidicJob::Base
          def perform
            Performance.performed!
          end
        end

        def perform
          with_acidic_workflow do |workflow|
            workflow.step :no_op, awaits: [SucJob]
          end
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :no_op, awaits: [WithSucChildAwaitCls]
        end
      end
    end

    perform_enqueued_jobs do
      WithSucGrandChildAwaitCls.perform_now
    end

    assert_equal 3, AcidicJob::Run.count
    assert_equal 1, Performance.performances

    grandparent_run = AcidicJob::Run.find_by(job_class: "TestCases::WithSucGrandChildAwaitCls")
    assert_equal "FINISHED", grandparent_run.recovery_point
    assert_equal true, grandparent_run.workflow?
    assert_equal false, grandparent_run.staged?
    assert_equal false, grandparent_run.awaited?

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::WithSucGrandChildAwaitCls::WithSucChildAwaitCls")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_equal true, parent_run.workflow?
    assert_equal true, parent_run.staged?
    assert_equal true, parent_run.awaited?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::WithSucGrandChildAwaitCls::WithSucChildAwaitCls::SucJob")
    assert_equal "FINISHED", child_run.recovery_point
    assert_equal false, child_run.workflow?
    assert_equal true, child_run.staged?
    assert_equal true, child_run.awaited?
  end

  test "nested workflow with all awaited job instances runs successfully" do
    class WithSucGrandChildAwaitInst < AcidicJob::Base
      class WithSucChildAwaitInst < AcidicJob::Base
        class SucJob < AcidicJob::Base
          def perform(_arg)
            Performance.performed!
          end
        end

        def perform(_arg)
          with_acidic_workflow do |workflow|
            workflow.step :no_op, awaits: [SucJob.with(123)]
          end
        end
      end

      def perform(_arg)
        with_acidic_workflow do |workflow|
          workflow.step :no_op, awaits: [WithSucChildAwaitInst.with(987)]
        end
      end
    end

    perform_enqueued_jobs do
      WithSucGrandChildAwaitInst.perform_now(567)
    end

    assert_equal 3, AcidicJob::Run.count
    assert_equal 1, Performance.performances

    grandparent_run = AcidicJob::Run.find_by(job_class: "TestCases::WithSucGrandChildAwaitInst")
    assert_equal "FINISHED", grandparent_run.recovery_point
    assert_equal true, grandparent_run.workflow?
    assert_equal false, grandparent_run.staged?
    assert_equal false, grandparent_run.awaited?

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::WithSucGrandChildAwaitInst::WithSucChildAwaitInst")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_equal true, parent_run.workflow?
    assert_equal true, parent_run.staged?
    assert_equal true, parent_run.awaited?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::WithSucGrandChildAwaitInst::WithSucChildAwaitInst::SucJob"
    )
    assert_equal "FINISHED", child_run.recovery_point
    assert_equal false, child_run.workflow?
    assert_equal true, child_run.staged?
    assert_equal true, child_run.awaited?
  end

  test "nested workflow with all awaited job classes with error in innermost job" do
    class WithErrGrandChildAwaitCls < AcidicJob::Base
      class WithErrChildAwaitCls < AcidicJob::Base
        class ErrJob < AcidicJob::Base
          def perform
            raise CustomErrorForTesting
          end
        end

        def perform
          with_acidic_workflow do |workflow|
            workflow.step :no_op, awaits: [ErrJob]
          end
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :no_op, awaits: [WithErrChildAwaitCls]
        end
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        WithErrGrandChildAwaitCls.perform_now
      end
    end

    assert_equal 3, AcidicJob::Run.count
    assert_equal 0, Performance.performances

    grandparent_run = AcidicJob::Run.find_by(job_class: "TestCases::WithErrGrandChildAwaitCls")
    assert_equal "no_op", grandparent_run.recovery_point
    assert_equal true, grandparent_run.workflow?
    assert_equal false, grandparent_run.staged?
    assert_equal false, grandparent_run.awaited?

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::WithErrGrandChildAwaitCls::WithErrChildAwaitCls")
    assert_equal "no_op", parent_run.recovery_point
    assert_equal true, parent_run.workflow?
    assert_equal true, parent_run.staged?
    assert_equal true, parent_run.awaited?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::WithErrGrandChildAwaitCls::WithErrChildAwaitCls::ErrJob")
    assert_nil child_run.recovery_point
    assert_equal false, child_run.workflow?
    assert_equal true, child_run.staged?
    assert_equal true, child_run.awaited?
  end

  test "nested workflow with all awaited job instances with error in innermost job" do
    class WithErrGrandChildAwaitInst < AcidicJob::Base
      class WithErrChildAwaitInst < AcidicJob::Base
        class ErrJob < AcidicJob::Base
          def perform(_arg)
            raise CustomErrorForTesting
          end
        end

        def perform(_arg)
          with_acidic_workflow do |workflow|
            workflow.step :no_op, awaits: [ErrJob.with(123)]
          end
        end
      end

      def perform(_arg)
        with_acidic_workflow do |workflow|
          workflow.step :no_op, awaits: [WithErrChildAwaitInst.with(987)]
        end
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        WithErrGrandChildAwaitInst.perform_now(567)
      end
    end

    assert_equal 3, AcidicJob::Run.count
    assert_equal 0, Performance.performances

    grandparent_run = AcidicJob::Run.find_by(job_class: "TestCases::WithErrGrandChildAwaitInst")
    assert_equal "no_op", grandparent_run.recovery_point
    assert_equal true, grandparent_run.workflow?
    assert_equal false, grandparent_run.staged?
    assert_equal false, grandparent_run.awaited?

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::WithErrGrandChildAwaitInst::WithErrChildAwaitInst")
    assert_equal "no_op", parent_run.recovery_point
    assert_equal true, parent_run.workflow?
    assert_equal true, parent_run.staged?
    assert_equal true, parent_run.awaited?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::WithErrGrandChildAwaitInst::WithErrChildAwaitInst::ErrJob"
    )
    assert_nil child_run.recovery_point
    assert_equal false, child_run.workflow?
    assert_equal true, child_run.staged?
    assert_equal true, child_run.awaited?
  end

  test "can persist ActiveRecord model instance in attributes" do
    class RecordPersisting < AcidicJob::Base
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

    run = AcidicJob::Run.find_by(job_class: "TestCases::RecordPersisting")
    assert_equal "FINISHED", run.recovery_point
    assert_equal 1, Notification.count
  end

  test "persisting ActiveRecord model instance in step method, then rollback" do
    class RecordPersistingThenRollback < AcidicJob::Base
      def perform
        with_acidic_workflow persisting: { notice: nil } do |workflow|
          workflow.step :do_something
        end
      end

      def do_something
        self.notice = Notification.create!(recipient_id: 1, recipient_type: "User")
        raise CustomErrorForTesting
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        RecordPersistingThenRollback.perform_now
      end
    end

    assert_equal 1, AcidicJob::Run.count

    run = AcidicJob::Run.find_by(job_class: "TestCases::RecordPersistingThenRollback")
    assert_equal "do_something", run.recovery_point
    assert_equal 0, Notification.count
  end

  test "if error while trying to persist error in step method, swallow but log error" do
    class ErrorUnlockingAfterError < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      end

      def do_something
        raise CustomErrorForTesting
      end
    end

    run = AcidicJob::Run.create!(
      idempotency_key: "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
      serialized_job: {
        "job_class" => "TestCases::ErrorUnlockingAfterError",
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
      job_class: "TestCases::ErrorUnlockingAfterError",
      last_run_at: Time.current,
      recovery_point: "do_something",
      workflow: {
        "do_something" => { "does" => "do_something", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
      }
    )
    # force an error occurring when AcidicJob is trying to unlock the run after a step method errors
    def run.store_error!(_error)
      raise RareErrorForTesting
    end
    AcidicJob::Run.stub(:find_by, ->(*) { run }) do
      assert_raises CustomErrorForTesting do
        ErrorUnlockingAfterError.perform_now
      end
    end

    run.reload
    assert !run.locked_at.nil?
    assert_equal false, run.succeeded?
  end

  test "deprecated `idempotently` syntax still works" do
    class Idempotently < AcidicJob::Base
      def perform
        idempotently do
          step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    Idempotently.perform_now

    assert_equal 1, AcidicJob::Run.count
    assert_equal 1, Performance.performances
  end

  test "deprecated `with_acidity` syntax still works" do
    class WithAcidity < AcidicJob::Base
      def perform
        with_acidity do
          step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    WithAcidity.perform_now

    assert_equal 1, AcidicJob::Run.count
    assert_equal 1, Performance.performances
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
