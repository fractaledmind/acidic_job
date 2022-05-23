# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
class TestCases < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def before_setup
    super()
    AcidicJob::Run.delete_all
    Performance.reset!
  end

  test "`AcidicJob::Base` only adds a few methods to job" do
    class BareJob < AcidicJob::Base; end

    assert_equal %i[_run_finish_callbacks _finish_callbacks with_acidic_workflow idempotency_key].sort,
                 (BareJob.instance_methods - ActiveJob::Base.instance_methods).sort
  end

  test "`AcidicJob::Base` in parent class adds methods to any job that inherit from parent" do
    class ParentJob < AcidicJob::Base; end
    class ChildJob < ParentJob; end

    assert_equal %i[_run_finish_callbacks _finish_callbacks with_acidic_workflow idempotency_key].sort,
                 (ChildJob.instance_methods - ActiveJob::Base.instance_methods).sort
  end

  test "calling `with_acidic_workflow` without a block raises `MissingWorkflowBlock`" do
    class JobWithoutBlock < AcidicJob::Base
      def perform
        with_acidic_workflow
      end
    end

    assert_raises AcidicJob::MissingWorkflowBlock do
      JobWithoutBlock.perform_now
    end
  end

  test "calling `with_acidic_workflow` with a block without steps raises `NoDefinedSteps`" do
    class JobWithoutSteps < AcidicJob::Base
      def perform
        with_acidic_workflow {} # rubocop:disable Lint/EmptyBlock
      end
    end

    assert_raises AcidicJob::NoDefinedSteps do
      JobWithoutSteps.perform_now
    end
  end

  test "calling `with_acidic_workflow` twice raises `RedefiningWorkflow`" do
    class JobWithDoubleWorkflow < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end

        with_acidic_workflow {} # rubocop:disable Lint/EmptyBlock
      end

      def do_something; end
    end

    assert_raises AcidicJob::RedefiningWorkflow do
      JobWithDoubleWorkflow.perform_now
    end
  end

  test "calling `with_acidic_workflow` with an undefined step method without `awaits` raises `UndefinedStepMethod`" do
    class JobWithUndefinedStep < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :no_op
        end
      end
    end

    assert_raises AcidicJob::UndefinedStepMethod do
      JobWithUndefinedStep.perform_now
    end
  end

  test "calling `with_acidic_workflow` with `persisting` unserializable value throws `TypeError` error" do
    class JobWithUnpersistableValue < AcidicJob::Base
      def perform
        with_acidic_workflow persisting: { key: -> { :some_proc } } do |workflow|
          workflow.step :do_something
        end
      end

      def do_something; end
    end

    assert_raises TypeError do
      JobWithUnpersistableValue.perform_now
    end
  end

  test "calling `with_acidic_workflow` with `persisting` serializes and saves the hash to the `Run` record" do
    class JobWithPersisting < AcidicJob::Base
      def perform
        with_acidic_workflow persisting: { key: :value } do |workflow|
          workflow.step :do_something
        end
      end

      def do_something; end
    end

    result = JobWithPersisting.perform_now
    assert_equal result, true
    run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithPersisting")
    assert_equal run.attr_accessors, { "key" => :value }
  end

  test "calling `idempotency_key` when `acidic_identifier` is unconfigured returns `job_id`" do
    class JobWithoutAcidicIdentifier < AcidicJob::Base
      def perform; end
    end

    job = JobWithoutAcidicIdentifier.new
    assert_equal job.job_id, job.idempotency_key
  end

  test "calling `idempotency_key` when `acidic_by_job_identifier` is set returns `job_id`" do
    class JobWithAcidicByIdentifier < AcidicJob::Base
      acidic_by_job_identifier

      def perform; end
    end

    job = JobWithAcidicByIdentifier.new
    assert_equal job.job_id, job.idempotency_key
  end

  test "calling `idempotency_key` when `acidic_by_job_arguments` is set returns hexidigest" do
    class JobWithAcidicByArguments < AcidicJob::Base
      acidic_by_job_arguments

      def perform; end
    end

    job = JobWithAcidicByArguments.new
    assert_equal "867593fcc38b8ee5709d61e4e9124def192d8f35", job.idempotency_key
  end

  test "calling `idempotency_key` when `acidic_by` is a block returns hexidigest" do
    class JobWithAcidicByArguments < AcidicJob::Base
      acidic_by do
        "a"
      end

      def perform; end
    end

    job = JobWithAcidicByArguments.new
    assert_equal "18a3c264100a68264d95a9a98d1aa115bd92107f", job.idempotency_key
  end

  test "basic one step workflow runs successfully" do
    class BasicJob < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    result = BasicJob.perform_now
    assert_equal true, result
    assert_equal true, Performance.performed_once?
  end

  test "an error raised in a step method is stored in the run record" do
    class ErroringJob < AcidicJob::Base
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
      ErroringJob.perform_now
    end

    run = AcidicJob::Run.find_by(job_class: "TestCases::ErroringJob")
    assert_equal CustomErrorForTesting, run.error_object.class
  end

  test "basic two step workflow runs successfully" do
    class TwoStepJob < AcidicJob::Base
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

    result = TwoStepJob.perform_now
    assert_equal true, result
    assert_equal 2, Performance.performances
  end

  test "basic two step workflow can be started from second step if pre-existing run record present" do
    class RestartedTwoStepJob < AcidicJob::Base
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

    run = AcidicJob::Run.create!(
      idempotency_key: "67b823ea-34f0-40a0-88d9-7e3b7ff9e769",
      serialized_job: {
        "job_class" => "TestCases::RestartedTwoStepJob",
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
      job_class: "TestCases::RestartedTwoStepJob",
      last_run_at: Time.current,
      recovery_point: "step_two",
      workflow: {
        "step_one" => { "does" => "step_one", "awaits" => [], "for_each" => nil, "then" => "step_two" },
        "step_two" => { "does" => "step_two", "awaits" => [], "for_each" => nil, "then" => "FINISHED" }
      }
    )
    AcidicJob::Run.stub(:find_by, ->(*) { run }) do
      result = RestartedTwoStepJob.perform_now
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
    class JobWithAfterFinishCallback < AcidicJob::Base
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

    result = JobWithAfterFinishCallback.perform_now
    assert_equal true, result
    assert_equal 0, AcidicJob::Run.count
  end

  test "`after_finish` callbacks don't run if job errors" do
    class ErroringJobWithAfterFinishCallback < AcidicJob::Base
      set_callback :finish, :after, :delete_run_record

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :do_something
        end
      end

      def do_something
        raise CustomErrorForTesting
      end

      def delete_run_record
        @acidic_job_run.destroy!
      end
    end

    assert_raises CustomErrorForTesting do
      ErroringJobWithAfterFinishCallback.perform_now
    end
    assert_equal 1, AcidicJob::Run.count
    assert_equal 1, AcidicJob::Run.where(job_class: "TestCases::ErroringJobWithAfterFinishCallback").count
  end

  test "rescued error in `perform` doesn't prevent `Run#error_object` from being stored" do
    class JobWithErrorAndRescueInPerform < AcidicJob::Base
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

    result = JobWithErrorAndRescueInPerform.perform_now
    assert_equal result, true
    assert_equal 1, AcidicJob::Run.count
    run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithErrorAndRescueInPerform")
    assert_equal CustomErrorForTesting, run.error_object.class
  end

  test "error in first step rolls back step transaction" do
    class JobWithErrorInStepMethod < AcidicJob::Base
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
      JobWithErrorInStepMethod.perform_now
    end

    assert_equal AcidicJob::Run.count, 1
    run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithErrorInStepMethod")
    assert_equal run.error_object.class, CustomErrorForTesting
    assert_equal run.attr_accessors, { "accessor" => nil }
  end

  test "logic inside `with_acidic_workflow` block is executed appropriately" do
    class JobWithSwitchOnStep < AcidicJob::Base
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
      JobWithSwitchOnStep.perform_now(true)
    end

    assert_raises AcidicJob::NoDefinedSteps do
      JobWithSwitchOnStep.perform_now(false)
    end

    assert_equal 1, AcidicJob::Run.count
  end

  test "invalid worker throws `UnknownJobAdapter` error" do
    assert_raises AcidicJob::UnknownJobAdapter do
      Class.new do
        include AcidicJob::Mixin
      end
    end
  end

  test "`with_acidic_workflow` always returns boolean, regardless of last value of the block" do
    class JobWithArbitraryReturnValue < AcidicJob::Base
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

    result = JobWithArbitraryReturnValue.perform_now
    assert_equal true, result
    assert_equal true, Performance.performed_once?
  end

  test "staged workflow job only creates on `AcidicJob::Run` record" do
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
      class SuccessfulAsyncJob < AcidicJob::Base
        def perform
          Performance.performed!
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [SuccessfulAsyncJob]
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

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::SimpleWorkflowJob::SuccessfulAsyncJob")
    assert_nil child_run.recovery_point
    assert_equal true, child_run.staged?

    assert_equal 2, Performance.performances
  end

  test "workflow job with erroring `awaits` job does not progress and does not store error object" do
    class WorkflowWithErroringAwaitsJob < AcidicJob::Base
      class ErroringAsyncJob < AcidicJob::Base
        def perform
          raise CustomErrorForTesting
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [ErroringAsyncJob]
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        WorkflowWithErroringAwaitsJob.perform_later
      end
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::WorkflowWithErroringAwaitsJob")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::WorkflowWithErroringAwaitsJob::ErroringAsyncJob")
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 0, Performance.performances
  end

  test "workflow job with successful `awaits` job that itself `awaits` another successful job" do
    class NestedSuccessfulAwaitSteps < AcidicJob::Base
      class SuccessfulAwaitedAndAwaits < AcidicJob::Base
        class NestedSuccessfulAwaited < AcidicJob::Base
          def perform
            Performance.performed!
          end
        end

        def perform
          with_acidic_workflow do |workflow|
            workflow.step :await_nested_step, awaits: [NestedSuccessfulAwaited]
          end
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [SuccessfulAwaitedAndAwaits]
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    perform_enqueued_jobs do
      NestedSuccessfulAwaitSteps.perform_later
    end

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::NestedSuccessfulAwaitSteps")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::NestedSuccessfulAwaitSteps::SuccessfulAwaitedAndAwaits"
    )
    assert_equal "FINISHED", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    grandchild_run = AcidicJob::Run.find_by(
      job_class: "TestCases::NestedSuccessfulAwaitSteps::SuccessfulAwaitedAndAwaits::NestedSuccessfulAwaited"
    )
    assert_nil grandchild_run.recovery_point
    assert_nil grandchild_run.error_object
    assert_equal true, grandchild_run.staged?

    assert_equal 2, Performance.performances
  end

  test "workflow job with successful `awaits` job that itself `awaits` another erroring job" do
    class JobWithNestedErroringAwaitSteps < AcidicJob::Base
      class SuccessfulAwaitedAndAwaitsJob < AcidicJob::Base
        class NestedErroringAwaitedJob < AcidicJob::Base
          def perform
            raise CustomErrorForTesting
          end
        end

        def perform
          with_acidic_workflow do |workflow|
            workflow.step :await_nested_step, awaits: [NestedErroringAwaitedJob]
          end
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [SuccessfulAwaitedAndAwaitsJob]
          workflow.step :do_something
        end
      end

      def do_something
        Performance.performed!
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        JobWithNestedErroringAwaitSteps.perform_later
      end
    end

    assert_equal 3, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithNestedErroringAwaitSteps")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::JobWithNestedErroringAwaitSteps::SuccessfulAwaitedAndAwaitsJob"
    )
    assert_equal "await_nested_step", child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    grandchild_run = AcidicJob::Run.find_by(
      job_class: "TestCases::JobWithNestedErroringAwaitSteps::SuccessfulAwaitedAndAwaitsJob::NestedErroringAwaitedJob"
    )
    assert_nil grandchild_run.recovery_point
    assert_nil grandchild_run.error_object
    assert_equal true, grandchild_run.staged?

    assert_equal 0, Performance.performances
  end

  test "workflow job with successful `awaits` initialized with arguments" do
    class JobWithSuccessfulArgAwaitStep < AcidicJob::Base
      class SuccessfulArgJob < AcidicJob::Base
        def perform(_arg)
          Performance.performed!
        end
      end

      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [SuccessfulArgJob.with(123)]
        end
      end
    end

    perform_enqueued_jobs do
      JobWithSuccessfulArgAwaitStep.perform_later
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithSuccessfulArgAwaitStep")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithSuccessfulArgAwaitStep::SuccessfulArgJob")
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 1, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as Symbol that returns successful awaited job" do
    class JobWithDynamicAwaitsAsSymbol < AcidicJob::Base
      class SuccessfulDynamicAwaitFromSymbolJob < AcidicJob::Base
        def perform(_arg)
          Performance.performed!
        end
      end

      class ErroringDynamicAwaitFromSymbolJob < AcidicJob::Base
        def perform
          raise CustomErrorForTesting
        end
      end

      def perform(bool)
        @bool = bool

        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        return [SuccessfulDynamicAwaitFromSymbolJob.with(123)] if @bool

        [ErroringDynamicAwaitFromSymbolJob]
      end
    end

    perform_enqueued_jobs do
      JobWithDynamicAwaitsAsSymbol.perform_later(true)
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithDynamicAwaitsAsSymbol")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::JobWithDynamicAwaitsAsSymbol::SuccessfulDynamicAwaitFromSymbolJob"
    )
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 1, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as Symbol that returns erroring awaited job" do
    class JobWithDynamicAwaitsAsSymbol < AcidicJob::Base
      class SuccessfulDynamicAwaitFromSymbolJob < AcidicJob::Base
        def perform(_arg)
          Performance.performed!
        end
      end

      class ErroringDynamicAwaitFromSymbolJob < AcidicJob::Base
        def perform
          raise CustomErrorForTesting
        end
      end

      def perform(bool)
        @bool = bool

        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: :dynamic_awaiting
        end
      end

      def dynamic_awaiting
        return [SuccessfulDynamicAwaitFromSymbolJob.with(123)] if @bool

        [ErroringDynamicAwaitFromSymbolJob]
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        JobWithDynamicAwaitsAsSymbol.perform_later(false)
      end
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithDynamicAwaitsAsSymbol")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::JobWithDynamicAwaitsAsSymbol::ErroringDynamicAwaitFromSymbolJob"
    )
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 0, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as String that returns successful awaited job" do
    class JobWithDynamicAwaitsAsString < AcidicJob::Base
      class SuccessfulDynamicAwaitFromStringJob < AcidicJob::Base
        def perform(_arg)
          Performance.performed!
        end
      end

      class ErroringDynamicAwaitFromStringJob < AcidicJob::Base
        def perform
          raise CustomErrorForTesting
        end
      end

      def perform(bool)
        @bool = bool

        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        return [SuccessfulDynamicAwaitFromStringJob.with(123)] if @bool

        [ErroringDynamicAwaitFromStringJob]
      end
    end

    perform_enqueued_jobs do
      JobWithDynamicAwaitsAsString.perform_later(true)
    end

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithDynamicAwaitsAsString")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::JobWithDynamicAwaitsAsString::SuccessfulDynamicAwaitFromStringJob"
    )
    assert_nil child_run.recovery_point
    assert_nil child_run.error_object
    assert_equal true, child_run.staged?

    assert_equal 1, Performance.performances
  end

  test "workflow job with dynamic `awaits` method as String that returns erroring awaited job" do
    class JobWithDynamicAwaitsAsString < AcidicJob::Base
      class SuccessfulDynamicAwaitFromStringJob < AcidicJob::Base
        def perform(_arg)
          Performance.performed!
        end
      end

      class ErroringDynamicAwaitFromStringJob < AcidicJob::Base
        def perform
          raise CustomErrorForTesting
        end
      end

      def perform(bool)
        @bool = bool

        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: "dynamic_awaiting"
        end
      end

      def dynamic_awaiting
        return [SuccessfulDynamicAwaitFromStringJob.with(123)] if @bool

        [ErroringDynamicAwaitFromStringJob]
      end
    end

    perform_enqueued_jobs do
      assert_raises CustomErrorForTesting do
        JobWithDynamicAwaitsAsString.perform_later(false)
      end
    end

    assert_equal 2, AcidicJob::Run.count

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::JobWithDynamicAwaitsAsString")
    assert_equal "await_step", parent_run.recovery_point
    assert_nil parent_run.error_object
    assert_equal false, parent_run.staged?

    child_run = AcidicJob::Run.find_by(
      job_class: "TestCases::JobWithDynamicAwaitsAsString::ErroringDynamicAwaitFromStringJob"
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
      def perform
        Performance.performed!
      end
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
        recovery_point: nil,
        workflow: nil,
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
          staged: false
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
    assert_nil run.recovery_point
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

    class AwaitingJob < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [JobNonWorkflowStagedAwaited]
        end
      end
    end

    perform_enqueued_jobs do
      AwaitingJob.perform_now
    end

    assert_equal 2, AcidicJob::Run.count
    assert_equal 1, Performance.performances

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::AwaitingJob")
    assert_equal "FINISHED", parent_run.recovery_point
    assert_equal true, parent_run.workflow?
    assert_equal false, parent_run.staged?
    assert_equal false, parent_run.awaited?

    child_run = AcidicJob::Run.find_by(job_class: "TestCases::JobNonWorkflowStagedAwaited")
    assert_nil child_run.recovery_point
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
    class AwaitingJob < AcidicJob::Base; end

    class JobWorkflowUnstagedAwaited < AcidicJob::Base
      def perform
        Performance.performed!
      end
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
        recovery_point: nil,
        workflow: nil,
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
          staged: false
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

    class AwaitingJob < AcidicJob::Base
      def perform
        with_acidic_workflow do |workflow|
          workflow.step :await_step, awaits: [JobWorkflowStagedAwaited]
        end
      end
    end

    perform_enqueued_jobs do
      AwaitingJob.perform_now
    end

    assert_equal 2, AcidicJob::Run.count
    assert_equal 1, Performance.performances

    parent_run = AcidicJob::Run.find_by(job_class: "TestCases::AwaitingJob")
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
end
# rubocop:enable Lint/ConstantDefinitionInBlock
