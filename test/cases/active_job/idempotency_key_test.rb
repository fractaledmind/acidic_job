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
        assert_equal "4ae41fb2fe4e33f819f42c3dcb5c0ae001cdc608", job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by` is a block returning array of strings returns hexidigest" do
        class AcidicByBlockWithArrayOfStrings < AcidicJob::Base
          acidic_by do
            %w[a b]
          end

          def perform; end
        end

        job = AcidicByBlockWithArrayOfStrings.new
        assert_equal "2cdcdb07113148a84a1d12198b0ea3bec74c7247", job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by` is a proc returning string returns hexidigest" do
        class AcidicByProcWithString < AcidicJob::Base
          acidic_by -> { "a" }

          def perform; end
        end

        job = AcidicByProcWithString.new
        assert_equal "3388db03d2eef3efabc68d092b98862b4b16a6a0", job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by` is a proc returning array of strings returns hexidigest" do
        class AcidicByProcWithArrayOfStrings < AcidicJob::Base
          acidic_by -> { %w[a b] }

          def perform; end
        end

        job = AcidicByProcWithArrayOfStrings.new
        assert_equal "db6c53f8a65317ed8db2b9c73d721efb5e07e9f6", job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by` is a block referencing instance variable defined in `perform` returns hexidigest" do
        class AcidicByBlockWithIvar < AcidicJob::Base
          acidic_by do
            @ivar
          end

          def perform
            @ivar = "a"
          end
        end

        job = AcidicByBlockWithIvar.new
        assert_equal "3fa0423c8bdac5b6b31e9f3b5bef5b4dc76c411f", job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by` is a block referencing array of instance variables defined in `perform` returns hexidigest" do
        class AcidicByBlockWithArrayOfIvars < AcidicJob::Base
          acidic_by do
            [@ivar1, @ivar2]
          end

          def perform
            @ivar1 = "a"
            @ivar2 = "b"
          end
        end

        job = AcidicByBlockWithArrayOfIvars.new
        assert_equal "b457cf301d7b086edbcac6c9745f6a13b70b88ea", job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by` is a proc referencing instance variable defined in `perform` returns hexidigest" do
        class AcidicByProcWithIvar < AcidicJob::Base
          acidic_by -> { @ivar }

          def perform
            @ivar = "a"
          end
        end

        job = AcidicByProcWithIvar.new
        assert_equal "296993b567116e170f9f2c84b382e43b645d12aa", job.idempotency_key
      end

      test "`idempotency_key` when `acidic_by` is a proc referencing array of instance variables defined in `perform` returns hexidigest" do
        class AcidicByProcWithArrayOfIvars < AcidicJob::Base
          acidic_by -> { [@ivar1, @ivar2] }

          def perform
            @ivar1 = "a"
            @ivar2 = "b"
          end
        end

        job = AcidicByProcWithArrayOfIvars.new
        assert_equal "9d8a13826c09cfa1bae14005f92112b36abb7ed0", job.idempotency_key
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
