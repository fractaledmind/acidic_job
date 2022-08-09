# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveKiq
    class IdempotencyKey < ActiveSupport::TestCase
      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
        Sidekiq::Queues.clear_all
        Sidekiq.redis(&:flushdb)
      end

      test "calling `idempotency_key` when `acidic_identifier` is unconfigured returns `job_id`" do
        class WithoutAcidicIdentifier < AcidicJob::ActiveKiq
          def perform; end
        end

        job = WithoutAcidicIdentifier.new
        assert_equal job.job_id, job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by_job_identifier` is set returns `job_id`" do
        class AcidicByIdentifier < AcidicJob::ActiveKiq
          acidic_by_job_identifier

          def perform; end
        end

        job = AcidicByIdentifier.new
        assert_equal job.job_id, job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by_job_arguments` is set returns hexidigest" do
        class AcidicByArguments < AcidicJob::ActiveKiq
          acidic_by_job_arguments

          def perform; end
        end

        job = AcidicByArguments.new
        assert_equal "139fbab71fc0e01e7ddc62cbe140b42fee13d4c5", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a block returning string returns hexidigest" do
        class AcidicByProcWithString < AcidicJob::ActiveKiq
          acidic_by do
            "a"
          end

          def perform; end
        end

        job = AcidicByProcWithString.new
        assert_equal "114b77d491a282da24f2f1c019e7d6d266d51a3a", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a block returning array of strings returns hexidigest" do
        class AcidicByProcWithArrayOfStrings < AcidicJob::ActiveKiq
          acidic_by do
            %w[a b]
          end

          def perform; end
        end

        job = AcidicByProcWithArrayOfStrings.new
        assert_equal "be88bf2c523b41a9112672015dcb5a05847cee8e", job.idempotency_key
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
