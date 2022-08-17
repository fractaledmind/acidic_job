# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

# rubocop:disable Lint/ConstantDefinitionInBlock, Layout/LineLength
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
        class AcidicByBlockWithString < AcidicJob::ActiveKiq
          acidic_by do
            "a"
          end

          def perform; end
        end

        job = AcidicByBlockWithString.new
        assert_equal "9224c11ec73bdd117d0349ebd32b7298dc284cba", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a block returning array of strings returns hexidigest" do
        class AcidicByBlockWithArrayOfStrings < AcidicJob::ActiveKiq
          acidic_by do
            %w[a b]
          end

          def perform; end
        end

        job = AcidicByBlockWithArrayOfStrings.new
        assert_equal "b7ad797b0385e5db5458c70f9900bbb9bbf5ebbb", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a proc returning string returns hexidigest" do
        class AcidicByProcWithString < AcidicJob::ActiveKiq
          acidic_by -> { "a" }

          def perform; end
        end

        job = AcidicByProcWithString.new
        assert_equal "114b77d491a282da24f2f1c019e7d6d266d51a3a", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a proc returning array of strings returns hexidigest" do
        class AcidicByProcWithArrayOfStrings < AcidicJob::ActiveKiq
          acidic_by -> { %w[a b] }

          def perform; end
        end

        job = AcidicByProcWithArrayOfStrings.new
        assert_equal "be88bf2c523b41a9112672015dcb5a05847cee8e", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a block referencing instance variable defined in `perform` returns hexidigest" do
        class AcidicByBlockWithIvar < AcidicJob::ActiveKiq
          acidic_by do
            @ivar
          end

          def perform
            @ivar = "a"
          end
        end

        job = AcidicByBlockWithIvar.new
        assert_equal "320432f688afb5257660c213546dcc48a698ceab", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a block referencing array of instance variables defined in `perform` returns hexidigest" do
        class AcidicByBlockWithArrayOfIvars < AcidicJob::ActiveKiq
          acidic_by do
            [@ivar1, @ivar2]
          end

          def perform
            @ivar1 = "a"
            @ivar2 = "b"
          end
        end

        job = AcidicByBlockWithArrayOfIvars.new
        assert_equal "ae64da6ee219622a7f78621aa99f25b995977488", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a proc referencing instance variable defined in `perform` returns hexidigest" do
        class AcidicByProcWithIvar < AcidicJob::ActiveKiq
          acidic_by -> { @ivar }

          def perform
            @ivar = "a"
          end
        end

        job = AcidicByProcWithIvar.new
        assert_equal "b433ddbadd4cfdb37288db7b81c47d53f254eafb", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is a proc referencing array of instance variables defined in `perform` returns hexidigest" do
        class AcidicByProcWithArrayOfIvars < AcidicJob::ActiveKiq
          acidic_by -> { [@ivar1, @ivar2] }

          def perform
            @ivar1 = "a"
            @ivar2 = "b"
          end
        end

        job = AcidicByProcWithArrayOfIvars.new
        assert_equal "6d47cb6ac29f8b57daebc594877172b3e82394d9", job.idempotency_key
      end

      test "calling `idempotency_key` when `acidic_by` is string gets ignored and returns `job_id`" do
        class AcidicByString < AcidicJob::ActiveKiq
          acidic_by "a"

          def perform; end
        end

        job = AcidicByString.new
        assert_equal job.job_id, job.idempotency_key
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock, Layout/LineLength
