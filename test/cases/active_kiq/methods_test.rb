# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

# rubocop:disable Lint/ConstantDefinitionInBlock
module Cases
  module ActiveKiq
    class Methods < ActiveSupport::TestCase
      include ::ActiveJob::TestHelper

      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!

        sidekiq_generated_methods = %i[
          sidekiq_options
          sidekiq_options=
          sidekiq_options_hash
          sidekiq_options_hash=
          sidekiq_retries_exhausted_block
          sidekiq_retries_exhausted_block=
          sidekiq_retry_in_block
          sidekiq_retry_in_block=
        ]
        @preexisting_methods = (
          ::Object.methods +
          ::Sidekiq::Worker.instance_methods +
          ::Sidekiq::JobUtil.instance_methods +
          sidekiq_generated_methods
        )
        @expected_methods = %i[
          __callbacks
          __callbacks?
          _finish_callbacks
          _perform_callbacks
          _run_finish_callbacks
          _run_perform_callbacks
          arguments
          arguments=
          deserialize
          enqueue
          idempotency_key
          idempotently
          job_id
          job_id=
          scheduled_at
          scheduled_at=
          perform
          perform_acidicly
          perform_later
          perform_now
          queue_name
          queue_name=
          run_callbacks
          safely_finish_acidic_job
          serialize
          with_acidic_workflow
          with_acidity
          set
        ].sort
      end

      test "`AcidicJob::ActiveKiq` only adds a few methods to job" do
        class BareJob < AcidicJob::ActiveKiq; end

        assert_equal @expected_methods,
                     (BareJob.instance_methods - @preexisting_methods).sort
      end

      test "`AcidicJob::ActiveKiq` in parent class adds methods to any job that inherit from parent" do
        class ParentJob < AcidicJob::ActiveKiq; end
        class ChildJob < ParentJob; end

        assert_equal @expected_methods,
                     (ChildJob.instance_methods - @preexisting_methods).sort
      end
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
