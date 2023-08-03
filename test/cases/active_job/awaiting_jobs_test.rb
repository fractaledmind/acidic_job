# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveJob
    class AwaitingJobs < ActiveSupport::TestCase
      include ::ActiveJob::TestHelper

      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
      end

      test "workflow job with successful awaits job runs successfully" do
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
          SimpleWorkflowJob.perform_now
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SimpleWorkflowJob"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SimpleWorkflowJob::SucAsyncJob"].join("::"))

        assert_equal "FINISHED", child_run.recovery_point
        assert_predicate child_run, :staged?

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
            WorkflowWithErrAwaitsJob.perform_now
          end
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "WorkflowWithErrAwaitsJob"].join("::"))

        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WorkflowWithErrAwaitsJob::ErrAsyncJob"].join("::")
        )

        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
          NestedSucAwaitSteps.perform_now
        end

        assert_equal 3, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "NestedSucAwaitSteps"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "NestedSucAwaitSteps::SucAwaitedAndAwaits"].join("::")
        )

        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

        grandchild_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "NestedSucAwaitSteps::SucAwaitedAndAwaits::NestedSucAwaited"].join("::")
        )

        assert_equal "FINISHED", grandchild_run.recovery_point
        assert_nil grandchild_run.error_object
        assert_predicate grandchild_run, :staged?

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
            NestedErrAwaitSteps.perform_now
          end
        end

        assert_equal 3, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "NestedErrAwaitSteps"].join("::"))

        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "NestedErrAwaitSteps::SucAwaitedAndAwaitsJob"].join("::")
        )

        assert_equal "await_nested_step", child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

        grandchild_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "NestedErrAwaitSteps::SucAwaitedAndAwaitsJob::NestedErrAwaitedJob"].join("::")
        )

        assert_nil grandchild_run.recovery_point
        assert_nil grandchild_run.error_object
        assert_predicate grandchild_run, :staged?

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
          SucArgAwaitStep.perform_now
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucArgAwaitStep"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucArgAwaitStep::SucArgJob"].join("::"))

        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
          SucDynamicAwaitClsAsSym.perform_now
        end

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucDynamicAwaitClsAsSym"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "SucDynamicAwaitClsAsSym::SucDynamicAwaitFromSymJob"].join("::")
        )

        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
          SucDynamicAwaitInstAsSym.perform_now
        end

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucDynamicAwaitInstAsSym"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "SucDynamicAwaitInstAsSym::SucDynamicAwaitFromSymJob"].join("::")
        )

        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
            ErrDynamicAwaitClsAsSym.perform_now
          end
        end

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrDynamicAwaitClsAsSym"].join("::"))

        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "ErrDynamicAwaitClsAsSym::ErrDynamicAwaitFromSymJob"].join("::")
        )

        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
            ErrDynamicAwaitInstAsSym.perform_now
          end
        end

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrDynamicAwaitInstAsSym"].join("::"))

        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "ErrDynamicAwaitInstAsSym::ErrDynamicAwaitFromSymJob"].join("::")
        )

        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
          SucDynamicAwaitClsAsString.perform_now
        end

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucDynamicAwaitClsAsString"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "SucDynamicAwaitClsAsString::SucDynamicAwaitFromStringJob"].join("::")
        )

        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
          SucDynamicAwaitInstAsString.perform_now
        end

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucDynamicAwaitInstAsString"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "SucDynamicAwaitInstAsString::SucDynamicAwaitFromStringJob"].join("::")
        )

        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
            ErrDynamicAwaitClsAsString.perform_now
          end
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrDynamicAwaitClsAsString"].join("::"))

        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "ErrDynamicAwaitClsAsString::ErrDynamicAwaitFromStringJob"].join("::")
        )

        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

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
            ErrDynamicAwaitInstAsString.perform_now
          end
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrDynamicAwaitInstAsString"].join("::"))

        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "ErrDynamicAwaitInstAsString::ErrDynamicAwaitFromStringJob"].join("::")
        )

        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

        assert_equal 0, Performance.performances
      end

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

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "JobAwaitingTwoJobs"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_predicate parent_run, :workflow?
        refute_predicate parent_run, :staged?
        refute_predicate parent_run, :awaited?

        first_child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "JobAwaitingTwoJobs::FirstAwaitedJob"].join("::")
        )

        assert_equal "FINISHED", first_child_run.recovery_point
        refute_predicate first_child_run, :workflow?
        assert_predicate first_child_run, :staged?
        assert_predicate first_child_run, :awaited?

        second_child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "JobAwaitingTwoJobs::SecondAwaitedJob"].join("::")
        )

        assert_equal "FINISHED", second_child_run.recovery_point
        assert_predicate second_child_run, :workflow?
        assert_predicate second_child_run, :staged?
        assert_predicate second_child_run, :awaited?
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

        grandparent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "WithSucGrandChildAwaitCls"].join("::"))

        assert_equal "FINISHED", grandparent_run.recovery_point
        assert_predicate grandparent_run, :workflow?
        refute_predicate grandparent_run, :staged?
        refute_predicate grandparent_run, :awaited?

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithSucGrandChildAwaitCls::WithSucChildAwaitCls"].join("::")
        )

        assert_equal "FINISHED", parent_run.recovery_point
        assert_predicate parent_run, :workflow?
        assert_predicate parent_run, :staged?
        assert_predicate parent_run, :awaited?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithSucGrandChildAwaitCls::WithSucChildAwaitCls::SucJob"].join("::")
        )

        assert_equal "FINISHED", child_run.recovery_point
        refute_predicate child_run, :workflow?
        assert_predicate child_run, :staged?
        assert_predicate child_run, :awaited?
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

        grandparent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "WithSucGrandChildAwaitInst"].join("::"))

        assert_equal "FINISHED", grandparent_run.recovery_point
        assert_predicate grandparent_run, :workflow?
        refute_predicate grandparent_run, :staged?
        refute_predicate grandparent_run, :awaited?

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithSucGrandChildAwaitInst::WithSucChildAwaitInst"].join("::")
        )

        assert_equal "FINISHED", parent_run.recovery_point
        assert_predicate parent_run, :workflow?
        assert_predicate parent_run, :staged?
        assert_predicate parent_run, :awaited?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithSucGrandChildAwaitInst::WithSucChildAwaitInst::SucJob"].join("::")
        )

        assert_equal "FINISHED", child_run.recovery_point
        refute_predicate child_run, :workflow?
        assert_predicate child_run, :staged?
        assert_predicate child_run, :awaited?
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

        grandparent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "WithErrGrandChildAwaitCls"].join("::"))

        assert_equal "no_op", grandparent_run.recovery_point
        assert_predicate grandparent_run, :workflow?
        refute_predicate grandparent_run, :staged?
        refute_predicate grandparent_run, :awaited?

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithErrGrandChildAwaitCls::WithErrChildAwaitCls"].join("::")
        )

        assert_equal "no_op", parent_run.recovery_point
        assert_predicate parent_run, :workflow?
        assert_predicate parent_run, :staged?
        assert_predicate parent_run, :awaited?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithErrGrandChildAwaitCls::WithErrChildAwaitCls::ErrJob"].join("::")
        )

        assert_nil child_run.recovery_point
        refute_predicate child_run, :workflow?
        assert_predicate child_run, :staged?
        assert_predicate child_run, :awaited?
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

        grandparent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "WithErrGrandChildAwaitInst"].join("::"))

        assert_equal "no_op", grandparent_run.recovery_point
        assert_predicate grandparent_run, :workflow?
        refute_predicate grandparent_run, :staged?
        refute_predicate grandparent_run, :awaited?

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithErrGrandChildAwaitInst::WithErrChildAwaitInst"].join("::")
        )

        assert_equal "no_op", parent_run.recovery_point
        assert_predicate parent_run, :workflow?
        assert_predicate parent_run, :staged?
        assert_predicate parent_run, :awaited?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithErrGrandChildAwaitInst::WithErrChildAwaitInst::ErrJob"].join("::")
        )

        assert_nil child_run.recovery_point
        refute_predicate child_run, :workflow?
        assert_predicate child_run, :staged?
        assert_predicate child_run, :awaited?
      end

      test "workflow job with successful awaits initialized with arguments defined in perform scope" do
        class SucArgScopeAwaitStep < AcidicJob::Base
          class SucArgJob < AcidicJob::Base
            def perform(arg)
              Performance.performed! unless arg.nil?
            end
          end

          def perform
            @arg = 123

            with_acidic_workflow do |workflow|
              workflow.step :await_step, awaits: [SucArgJob.with(@arg)]
            end
          end
        end

        perform_enqueued_jobs do
          SucArgScopeAwaitStep.perform_now
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucArgScopeAwaitStep"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        assert_nil parent_run.error_object
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucArgScopeAwaitStep::SucArgJob"].join("::"))

        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_predicate child_run, :staged?

        assert_equal 1, Performance.performances
      end

      test "awaiting method that returns single job runs successfully" do
        class AwaitMethodSingleJob < AcidicJob::Base
          class SucAsyncJob < AcidicJob::Base
            def perform
              Performance.performed!
            end
          end

          def perform
            with_acidic_workflow do |workflow|
              workflow.step :await_step, awaits: :job_to_await
              workflow.step :do_something
            end
          end

          def do_something
            Performance.performed!
          end

          def job_to_await
            SucAsyncJob
          end
        end

        perform_enqueued_jobs do
          AwaitMethodSingleJob.perform_now
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "AwaitMethodSingleJob"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name, "AwaitMethodSingleJob::SucAsyncJob"].join("::"))

        assert_equal "FINISHED", child_run.recovery_point
        assert_predicate child_run, :staged?

        assert_equal 2, Performance.performances
      end

      test "workflow job with forced sleep before with_lock runs successfully" do
        class WorkflowJobWithForcedSleepBeforeLock < AcidicJob::Base
          class SucAsyncJob < AcidicJob::Base
            def perform(_arg)
              Performance.performed!
            end
          end

          def perform
            with_acidic_workflow do |workflow|
              # this needs to await a job **instance**
              workflow.step :await_step, awaits: [SucAsyncJob.with("argument")]
              workflow.step :do_something
            end
          end

          def do_something
            Performance.performed!
          end
        end

        trace = TracePoint.new(:call) do |tp|
          # when `Workflow#run_current_step` calls `AcidicJob.logger.log_run_event("Executing #{current_step}...")`,
          # we can pause for 1 second to ensure the serialized job in the `Run#workflow` has a different `enqueued_at`
          if (tp.defined_class == AcidicJob::Logger) &&
             (tp.method_id == :log_run_event) &&
             (tp.binding.local_variable_get(:msg).start_with? "Executing")
            sleep 1
          end
        end

        perform_enqueued_jobs do
          trace.enable do
            WorkflowJobWithForcedSleepBeforeLock.perform_now
          end
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name,
                                                        "WorkflowJobWithForcedSleepBeforeLock"].join("::"))

        assert_equal "FINISHED", parent_run.recovery_point
        refute_predicate parent_run, :staged?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name,
                                                       "WorkflowJobWithForcedSleepBeforeLock::SucAsyncJob"].join("::"))

        assert_equal "FINISHED", child_run.recovery_point
        assert_predicate child_run, :staged?

        assert_equal 2, Performance.performances
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
