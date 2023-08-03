# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveKiq
    class StagedJobs < ActiveSupport::TestCase
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

      test "staged workflow job only creates one AcidicJob::Run record" do
        class StagedWorkflowJob < AcidicJob::ActiveKiq
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

        run = AcidicJob::Run.find_by(job_class: [self.class.name, "StagedWorkflowJob"].join("::"))

        assert_equal "FINISHED", run.recovery_point
        assert_equal 1, Performance.performances
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
