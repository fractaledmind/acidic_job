# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock, Layout/LineLength
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

      test "`idempotency_key` when `acidic_identifier` is unconfigured returns `job_id`" do
        class WithoutAcidicIdentifier < AcidicJob::Base
          def perform; end
        end

        job = WithoutAcidicIdentifier.new
        assert_equal job.job_id, job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by_job_identifier` is set returns `job_id`" do
        class AcidicByIdentifier < AcidicJob::Base
          acidic_by_job_identifier

          def perform; end
        end

        job = AcidicByIdentifier.new
        assert_equal job.job_id, job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by_job_arguments` is set returns hexidigest" do
        class AcidicByArguments < AcidicJob::Base
          acidic_by_job_arguments

          def perform; end
        end

        job = AcidicByArguments.new
        assert_equal "3fec03d97f0a26542aac31756ba98a140b049c21", job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by` is a block returning string returns hexidigest" do
        class AcidicByBlockWithString < AcidicJob::Base
          acidic_by do
            "a"
          end

          def perform; end
        end

        job = AcidicByBlockWithString.new
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "4ae41fb2fe4e33f819f42c3dcb5c0ae001cdc608", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a block returning array of strings returns hexidigest" do
        class AcidicByBlockWithArrayOfStrings < AcidicJob::Base
          acidic_by do
            %w[a b]
          end

          def perform; end
        end

        job = AcidicByBlockWithArrayOfStrings.new
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "2cdcdb07113148a84a1d12198b0ea3bec74c7247", job.idempotency_key
        assert_equal %w[a b], acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a proc returning string returns hexidigest" do
        class AcidicByProcWithString < AcidicJob::Base
          acidic_by -> { "a" }

          def perform; end
        end

        job = AcidicByProcWithString.new
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "3388db03d2eef3efabc68d092b98862b4b16a6a0", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a proc returning array of strings returns hexidigest" do
        class AcidicByProcWithArrayOfStrings < AcidicJob::Base
          acidic_by -> { %w[a b] }

          def perform; end
        end

        job = AcidicByProcWithArrayOfStrings.new
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "db6c53f8a65317ed8db2b9c73d721efb5e07e9f6", job.idempotency_key
        assert_equal %w[a b], acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a block referencing instance variable defined in `perform` returns hexidigest" do
        class AcidicByBlockWithArg < AcidicJob::Base
          acidic_by do
            arguments[0]
          end

          def perform; end
        end

        job = AcidicByBlockWithArg.new("a")
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "dc4a6ecd3e9f2abae48e095e419baf9e7b24d464", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a block referencing array of instance variables defined in `perform` returns hexidigest" do
        class AcidicByBlockWithArgs < AcidicJob::Base
          acidic_by do
            arguments
          end

          def perform; end
        end

        job = AcidicByBlockWithArgs.new("a", "b")
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "8540d60e1c53f7c36e21a0c3d5a21c542c2638fa", job.idempotency_key
        assert_equal %w[a b], acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a block returning job `argument` keyword returns hexidigest" do
        class AcidicByBlockWithArgValue < AcidicJob::Base
          acidic_by do
            item = arguments.first[:a]
            item.value
          end

          def perform; end
        end

        job = AcidicByBlockWithArgValue.new(a: Struct.new(:value).new("a"))
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "7b05d03f4ee4176a1e6604bf14b84f0750c39947", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a proc referencing job `arguments` returns hexidigest" do
        class AcidicByProcWithArg < AcidicJob::Base
          acidic_by -> { arguments[0] }

          def perform; end
        end

        job = AcidicByProcWithArg.new("a")
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "2870cf6d05c9cd9f6b988571fd416c9e1c43fdd0", job.idempotency_key
        assert_equal "a", acidic_by
      end

      test "`idempotency_key` when `acidic_by` is a proc referencing array of job `arguments` returns hexidigest" do
        class AcidicByProcWithArgs < AcidicJob::Base
          acidic_by -> { arguments }

          def perform; end
        end

        job = AcidicByProcWithArgs.new("a", "b")
        acidic_by = job.instance_exec(&job.send(:acidic_identifier))
        assert_equal "16e6be9d979300279a30cdd7e1a058b928c9355d", job.idempotency_key
        assert_equal %w[a b], acidic_by
      end

      test "`idempotency_key` when `acidic_by` is string gets ignored and returns `job_id`" do
        class AcidicByString < AcidicJob::Base
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
