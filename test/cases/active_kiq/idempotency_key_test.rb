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
        class AcidicByBlockWithString < AcidicJob::ActiveKiq
          acidic_by do
            "a"
          end

          def perform; end
        end

        job = AcidicByBlockWithString.new
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "9224c11ec73bdd117d0349ebd32b7298dc284cba", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "calling `idempotency_key` when `acidic_by` is a block returning array of strings returns hexidigest" do
        class AcidicByBlockWithArrayOfStrings < AcidicJob::ActiveKiq
          acidic_by do
            %w[a b]
          end

          def perform; end
        end

        job = AcidicByBlockWithArrayOfStrings.new
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "b7ad797b0385e5db5458c70f9900bbb9bbf5ebbb", job.idempotency_key
        assert_equal %w[a b], acidic_by
      end

      test "calling `idempotency_key` when `acidic_by` is a proc returning string returns hexidigest" do
        class AcidicByProcWithString < AcidicJob::ActiveKiq
          acidic_by -> { "a" }

          def perform; end
        end

        job = AcidicByProcWithString.new
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "114b77d491a282da24f2f1c019e7d6d266d51a3a", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "calling `idempotency_key` when `acidic_by` is a proc returning array of strings returns hexidigest" do
        class AcidicByProcWithArrayOfStrings < AcidicJob::ActiveKiq
          acidic_by -> { %w[a b] }

          def perform; end
        end

        job = AcidicByProcWithArrayOfStrings.new
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "be88bf2c523b41a9112672015dcb5a05847cee8e", job.idempotency_key
        assert_equal %w[a b], acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a block returning first job `argument` returns hexidigest" do
        class AcidicByBlockWithArg < AcidicJob::ActiveKiq
          acidic_by do
            arguments[0]
          end

          def perform; end
        end

        job = AcidicByBlockWithArg.new("a")
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "d45b028573700da1cfcf42c3c1c9376ad4096367", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a block returning job `arguments` returns hexidigest" do
        class AcidicByBlockWithArgs < AcidicJob::ActiveKiq
          acidic_by do
            arguments
          end

          def perform; end
        end

        job = AcidicByBlockWithArgs.new("a", "b")
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "0c2e48298c4230181efe7aee3f52e83a654e1ddd", job.idempotency_key
        assert_equal %w[a b], acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a block returning job `argument` keyword returns hexidigest" do
        class AcidicByBlockWithArgValue < AcidicJob::ActiveKiq
          acidic_by do
            item = arguments.first[:a]
            item.value
          end

          def perform; end
        end

        job = AcidicByBlockWithArgValue.new(a: Struct.new(:value).new("a"))
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "9c80defa6aab346fca1262aea92f1fb50ae9334b", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a proc referencing job `arguments` returns hexidigest" do
        class AcidicByProcWithArg < AcidicJob::ActiveKiq
          acidic_by -> { arguments[0] }

          def perform; end
        end

        job = AcidicByProcWithArg.new("a")
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "fe26283a2d755668961e45f6f038e9b79ebea9c5", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a proc referencing array of job `arguments` returns hexidigest" do
        class AcidicByProcWithArgs < AcidicJob::ActiveKiq
          acidic_by -> { arguments }

          def perform; end
        end

        job = AcidicByProcWithArgs.new("a", "b")
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))

        assert_equal "c8d1703b5eeecc751fcdba542be49a6192cc2727", job.idempotency_key
        assert_equal %w[a b], acidic_by
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
# rubocop:enable Lint/ConstantDefinitionInBlock
