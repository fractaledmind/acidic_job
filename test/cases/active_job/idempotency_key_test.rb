# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveJob
    class IdempotencyKey < ActiveSupport::TestCase
      include ::ActiveJob::TestHelper

      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
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
        assert_equal "3fec03d97f0a26542aac31756ba98a140b049c21", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a block returning string returns hexidigest" do
        class AcidicByProcWithString < AcidicJob::Base
          acidic_by do
            "a"
          end

          def perform; end
        end

        job = AcidicByProcWithString.new
        assert_equal "3388db03d2eef3efabc68d092b98862b4b16a6a0", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a block returning array of strings returns hexidigest" do
        class AcidicByProcWithArrayOfStrings < AcidicJob::Base
          acidic_by do
            %w[a b]
          end

          def perform; end
        end

        job = AcidicByProcWithArrayOfStrings.new
        assert_equal "db6c53f8a65317ed8db2b9c73d721efb5e07e9f6", job.idempotency_key
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
