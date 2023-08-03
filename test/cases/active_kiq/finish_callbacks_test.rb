# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveKiq
    class FinishCallbacks < ActiveSupport::TestCase
      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
        Sidekiq::Queues.clear_all
        Sidekiq.redis(&:flushdb)
      end

      test "can define `after_finish` callbacks" do
        class AfterFinishCallback < AcidicJob::ActiveKiq
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

        assert result
        assert_equal 0, AcidicJob::Run.count
      end

      test "`after_finish` callbacks don't run if job errors" do
        class ErrAfterFinishCallback < AcidicJob::ActiveKiq
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
        assert_equal 1, AcidicJob::Run.where(job_class: [self.class.name, "ErrAfterFinishCallback"].join("::")).count
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
