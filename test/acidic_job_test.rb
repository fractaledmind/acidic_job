# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
class ActiveJobTestCases < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def before_setup
    super()
    AcidicJob::Run.delete_all
    Notification.delete_all
    Performance.reset!
  end

  test "`AcidicJob::Base` only adds a few methods to job" do
    class BareJob < AcidicJob::Base; end

    expected_methods = %i[
      _run_finish_callbacks
      _finish_callbacks
      with_acidic_workflow
      idempotency_key
      safely_finish_acidic_job
      idempotently
      with_acidity
    ].sort
    assert_equal expected_methods,
                 (BareJob.instance_methods - ActiveJob::Base.instance_methods).sort
  end

  test "`AcidicJob::Base` in parent class adds methods to any job that inherit from parent" do
    class ParentJob < AcidicJob::Base; end
    class ChildJob < ParentJob; end

    expected_methods = %i[
      _run_finish_callbacks
      _finish_callbacks
      with_acidic_workflow
      idempotency_key
      safely_finish_acidic_job
      idempotently
      with_acidity
    ].sort
    assert_equal expected_methods,
                 (ChildJob.instance_methods - ActiveJob::Base.instance_methods).sort
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
