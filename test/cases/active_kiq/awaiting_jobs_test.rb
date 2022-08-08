# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveKiq
    class AwaitingJobs < ActiveSupport::TestCase
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

      test "workflow job with successful awaits job runs successfully" do
        class SimpleWorkflowJob < AcidicJob::ActiveKiq
          class SucAsyncJob < AcidicJob::ActiveKiq
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
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SimpleWorkflowJob::SucAsyncJob"].join("::"))
        assert_equal "FINISHED", child_run.recovery_point
        assert_equal true, child_run.staged?

        assert_equal 2, Performance.performances
      end

      test "workflow job with erroring `awaits` job does not progress and does not store error object" do
        class WorkflowWithErrAwaitsJob < AcidicJob::ActiveKiq
          class ErrAsyncJob < AcidicJob::ActiveKiq
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

        assert_raises CustomErrorForTesting do
          perform_enqueued_jobs do
            WorkflowWithErrAwaitsJob.perform_now
          end
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "WorkflowWithErrAwaitsJob"].join("::"))
        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WorkflowWithErrAwaitsJob::ErrAsyncJob"].join("::")
        )
        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 0, Performance.performances
      end

      test "workflow job with successful awaits job that itself awaits another successful job" do
        class NestedSucAwaitSteps < AcidicJob::ActiveKiq
          class SucAwaitedAndAwaits < AcidicJob::ActiveKiq
            class NestedSucAwaited < AcidicJob::ActiveKiq
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
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "NestedSucAwaitSteps::SucAwaitedAndAwaits"].join("::")
        )
        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        grandchild_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "NestedSucAwaitSteps::SucAwaitedAndAwaits::NestedSucAwaited"].join("::")
        )
        assert_equal "FINISHED", grandchild_run.recovery_point
        assert_nil grandchild_run.error_object
        assert_equal true, grandchild_run.staged?

        assert_equal 2, Performance.performances
      end

      test "workflow job with successful `awaits` job that itself `awaits` another erroring job" do
        class NestedErrAwaitSteps < AcidicJob::ActiveKiq
          class SucAwaitedAndAwaitsJob < AcidicJob::ActiveKiq
            class NestedErrAwaitedJob < AcidicJob::ActiveKiq
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

        assert_raises CustomErrorForTesting do
          perform_enqueued_jobs do
            NestedErrAwaitSteps.perform_now
          end
        end

        assert_equal 3, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "NestedErrAwaitSteps"].join("::"))
        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "NestedErrAwaitSteps::SucAwaitedAndAwaitsJob"].join("::")
        )
        assert_equal "await_nested_step", child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        grandchild_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "NestedErrAwaitSteps::SucAwaitedAndAwaitsJob::NestedErrAwaitedJob"].join("::")
        )
        assert_nil grandchild_run.recovery_point
        assert_nil grandchild_run.error_object
        assert_equal true, grandchild_run.staged?

        assert_equal 0, Performance.performances
      end

      test "workflow job with successful awaits initialized with arguments" do
        class SucArgAwaitStep < AcidicJob::ActiveKiq
          class SucArgJob < AcidicJob::ActiveKiq
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
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(job_class: [self.class.name, "SucArgAwaitStep::SucArgJob"].join("::"))
        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 1, Performance.performances
      end

      test "workflow job with dynamic `awaits` method as Symbol that returns successful awaited job class" do
        class SucDynamicAwaitClsAsSym < AcidicJob::ActiveKiq
          class SucDynamicAwaitFromSymJob < AcidicJob::ActiveKiq
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
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "SucDynamicAwaitClsAsSym::SucDynamicAwaitFromSymJob"].join("::")
        )
        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 1, Performance.performances
      end

      test "workflow job with dynamic `awaits` method as Symbol that returns successful awaited job instance" do
        class SucDynamicAwaitInstAsSym < AcidicJob::ActiveKiq
          class SucDynamicAwaitFromSymJob < AcidicJob::ActiveKiq
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
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "SucDynamicAwaitInstAsSym::SucDynamicAwaitFromSymJob"].join("::")
        )
        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 1, Performance.performances
      end

      test "workflow job with dynamic `awaits` method as Symbol that returns erroring awaited job class" do
        class ErrDynamicAwaitClsAsSym < AcidicJob::ActiveKiq
          class ErrDynamicAwaitFromSymJob < AcidicJob::ActiveKiq
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

        assert_raises CustomErrorForTesting do
          perform_enqueued_jobs do
            ErrDynamicAwaitClsAsSym.perform_now
          end
        end

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrDynamicAwaitClsAsSym"].join("::"))
        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "ErrDynamicAwaitClsAsSym::ErrDynamicAwaitFromSymJob"].join("::")
        )
        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 0, Performance.performances
      end

      test "workflow job with dynamic `awaits` method as Symbol that returns erroring awaited job instance" do
        class ErrDynamicAwaitInstAsSym < AcidicJob::ActiveKiq
          class ErrDynamicAwaitFromSymJob < AcidicJob::ActiveKiq
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

        assert_raises CustomErrorForTesting do
          perform_enqueued_jobs do
            ErrDynamicAwaitInstAsSym.perform_now
          end
        end

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrDynamicAwaitInstAsSym"].join("::"))
        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "ErrDynamicAwaitInstAsSym::ErrDynamicAwaitFromSymJob"].join("::")
        )
        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 0, Performance.performances
      end

      test "workflow job with dynamic `awaits` method as String that returns successful awaited job class" do
        class SucDynamicAwaitClsAsString < AcidicJob::ActiveKiq
          class SucDynamicAwaitFromStringJob < AcidicJob::ActiveKiq
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
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "SucDynamicAwaitClsAsString::SucDynamicAwaitFromStringJob"].join("::")
        )
        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 1, Performance.performances
      end

      test "workflow job with dynamic `awaits` method as String that returns successful awaited job instance" do
        class SucDynamicAwaitInstAsString < AcidicJob::ActiveKiq
          class SucDynamicAwaitFromStringJob < AcidicJob::ActiveKiq
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
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "SucDynamicAwaitInstAsString::SucDynamicAwaitFromStringJob"].join("::")
        )
        assert_equal "FINISHED", child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 1, Performance.performances
      end

      test "workflow job with dynamic `awaits` method as String that returns erroring awaited job class" do
        class ErrDynamicAwaitClsAsString < AcidicJob::ActiveKiq
          class ErrDynamicAwaitFromStringJob < AcidicJob::ActiveKiq
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

        assert_raises CustomErrorForTesting do
          perform_enqueued_jobs do
            ErrDynamicAwaitClsAsString.perform_now
          end
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrDynamicAwaitClsAsString"].join("::"))
        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "ErrDynamicAwaitClsAsString::ErrDynamicAwaitFromStringJob"].join("::")
        )
        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 0, Performance.performances
      end

      test "workflow job with dynamic `awaits` method as String that returns erroring awaited job instance" do
        class ErrDynamicAwaitInstAsString < AcidicJob::ActiveKiq
          class ErrDynamicAwaitFromStringJob < AcidicJob::ActiveKiq
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

        assert_raises CustomErrorForTesting do
          perform_enqueued_jobs do
            ErrDynamicAwaitInstAsString.perform_now
          end
        end

        assert_equal 2, AcidicJob::Run.count

        parent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "ErrDynamicAwaitInstAsString"].join("::"))
        assert_equal "await_step", parent_run.recovery_point
        assert_nil parent_run.error_object
        assert_equal false, parent_run.staged?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "ErrDynamicAwaitInstAsString::ErrDynamicAwaitFromStringJob"].join("::")
        )
        assert_nil child_run.recovery_point
        assert_nil child_run.error_object
        assert_equal true, child_run.staged?

        assert_equal 0, Performance.performances
      end

      test "basic one step workflow awaiting 2 jobs runs successfully" do
        class JobAwaitingTwoJobs < AcidicJob::ActiveKiq
          class FirstAwaitedJob < AcidicJob::ActiveKiq
            def perform
              Performance.performed!
            end
          end

          class SecondAwaitedJob < AcidicJob::ActiveKiq
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
        assert_equal true, parent_run.workflow?
        assert_equal false, parent_run.staged?
        assert_equal false, parent_run.awaited?

        first_child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "JobAwaitingTwoJobs::FirstAwaitedJob"].join("::")
        )
        assert_equal "FINISHED", first_child_run.recovery_point
        assert_equal false, first_child_run.workflow?
        assert_equal true, first_child_run.staged?
        assert_equal true, first_child_run.awaited?

        second_child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "JobAwaitingTwoJobs::SecondAwaitedJob"].join("::")
        )
        assert_equal "FINISHED", second_child_run.recovery_point
        assert_equal true, second_child_run.workflow?
        assert_equal true, second_child_run.staged?
        assert_equal true, second_child_run.awaited?
      end

      test "nested workflow with all awaited job classes runs successfully" do
        class WithSucGrandChildAwaitCls < AcidicJob::ActiveKiq
          class WithSucChildAwaitCls < AcidicJob::ActiveKiq
            class SucJob < AcidicJob::ActiveKiq
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
        assert_equal true, grandparent_run.workflow?
        assert_equal false, grandparent_run.staged?
        assert_equal false, grandparent_run.awaited?

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithSucGrandChildAwaitCls::WithSucChildAwaitCls"].join("::")
        )
        assert_equal "FINISHED", parent_run.recovery_point
        assert_equal true, parent_run.workflow?
        assert_equal true, parent_run.staged?
        assert_equal true, parent_run.awaited?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithSucGrandChildAwaitCls::WithSucChildAwaitCls::SucJob"].join("::")
        )
        assert_equal "FINISHED", child_run.recovery_point
        assert_equal false, child_run.workflow?
        assert_equal true, child_run.staged?
        assert_equal true, child_run.awaited?
      end

      test "nested workflow with all awaited job instances runs successfully" do
        class WithSucGrandChildAwaitInst < AcidicJob::ActiveKiq
          class WithSucChildAwaitInst < AcidicJob::ActiveKiq
            class SucJob < AcidicJob::ActiveKiq
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
        assert_equal true, grandparent_run.workflow?
        assert_equal false, grandparent_run.staged?
        assert_equal false, grandparent_run.awaited?

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithSucGrandChildAwaitInst::WithSucChildAwaitInst"].join("::")
        )
        assert_equal "FINISHED", parent_run.recovery_point
        assert_equal true, parent_run.workflow?
        assert_equal true, parent_run.staged?
        assert_equal true, parent_run.awaited?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithSucGrandChildAwaitInst::WithSucChildAwaitInst::SucJob"].join("::")
        )
        assert_equal "FINISHED", child_run.recovery_point
        assert_equal false, child_run.workflow?
        assert_equal true, child_run.staged?
        assert_equal true, child_run.awaited?
      end

      test "nested workflow with all awaited job classes with error in innermost job" do
        class WithErrGrandChildAwaitCls < AcidicJob::ActiveKiq
          class WithErrChildAwaitCls < AcidicJob::ActiveKiq
            class ErrJob < AcidicJob::ActiveKiq
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

        assert_raises CustomErrorForTesting do
          perform_enqueued_jobs do
            WithErrGrandChildAwaitCls.perform_now
          end
        end

        assert_equal 3, AcidicJob::Run.count
        assert_equal 0, Performance.performances

        grandparent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "WithErrGrandChildAwaitCls"].join("::"))
        assert_equal "no_op", grandparent_run.recovery_point
        assert_equal true, grandparent_run.workflow?
        assert_equal false, grandparent_run.staged?
        assert_equal false, grandparent_run.awaited?

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithErrGrandChildAwaitCls::WithErrChildAwaitCls"].join("::")
        )
        assert_equal "no_op", parent_run.recovery_point
        assert_equal true, parent_run.workflow?
        assert_equal true, parent_run.staged?
        assert_equal true, parent_run.awaited?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithErrGrandChildAwaitCls::WithErrChildAwaitCls::ErrJob"].join("::")
        )
        assert_nil child_run.recovery_point
        assert_equal false, child_run.workflow?
        assert_equal true, child_run.staged?
        assert_equal true, child_run.awaited?
      end

      test "nested workflow with all awaited job instances with error in innermost job" do
        class WithErrGrandChildAwaitInst < AcidicJob::ActiveKiq
          class WithErrChildAwaitInst < AcidicJob::ActiveKiq
            class ErrJob < AcidicJob::ActiveKiq
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

        assert_raises CustomErrorForTesting do
          perform_enqueued_jobs do
            WithErrGrandChildAwaitInst.perform_now(567)
          end
        end

        assert_equal 3, AcidicJob::Run.count
        assert_equal 0, Performance.performances

        grandparent_run = AcidicJob::Run.find_by(job_class: [self.class.name, "WithErrGrandChildAwaitInst"].join("::"))
        assert_equal "no_op", grandparent_run.recovery_point
        assert_equal true, grandparent_run.workflow?
        assert_equal false, grandparent_run.staged?
        assert_equal false, grandparent_run.awaited?

        parent_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithErrGrandChildAwaitInst::WithErrChildAwaitInst"].join("::")
        )
        assert_equal "no_op", parent_run.recovery_point
        assert_equal true, parent_run.workflow?
        assert_equal true, parent_run.staged?
        assert_equal true, parent_run.awaited?

        child_run = AcidicJob::Run.find_by(
          job_class: [self.class.name, "WithErrGrandChildAwaitInst::WithErrChildAwaitInst::ErrJob"].join("::")
        )
        assert_nil child_run.recovery_point
        assert_equal false, child_run.workflow?
        assert_equal true, child_run.staged?
        assert_equal true, child_run.awaited?
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
