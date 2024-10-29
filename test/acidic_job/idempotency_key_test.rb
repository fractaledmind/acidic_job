# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

class AcidicJob::IdempotencyKey < ActiveSupport::TestCase
  include ::ActiveJob::TestHelper

  def before_setup
    Performance.reset!
    AcidicJob::Value.delete_all
    AcidicJob::Entry.delete_all
    AcidicJob::Execution.delete_all
    TestObject.delete_all
  end

  def after_teardown
  end

  test "`unique_by` unconfigured returns `job_id`" do
    class WithoutAcidicIdentifier < ActiveJob::Base
      include AcidicJob::Workflow

      def perform; end
    end

    job = WithoutAcidicIdentifier.new

    assert_equal job.job_id, job.unique_by
  end

  test "`idempotency_key` when `unique_by = arguments` is set returns hexidigest" do
    class AcidicByArguments < ActiveJob::Base
      include AcidicJob::Workflow

      def unique_by; arguments; end

      def perform; end
    end

    job = AcidicByArguments.new

    assert_equal "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945", job.idempotency_key
  end

  test "`idempotency_key` when `unique_by` is a static string returns hexidigest" do
    class AcidicByBlockWithString < ActiveJob::Base
      include AcidicJob::Workflow

      def unique_by; "a"; end

      def perform; end
    end

    job = AcidicByBlockWithString.new

    assert_equal "ac8d8342bbb2362d13f0a559a3621bb407011368895164b628a54f7fc33fc43c", job.idempotency_key
  end

  test "`idempotency_key` when `unique_by` is an array of strings returns hexidigest" do
    class AcidicByBlockWithArrayOfStrings < ActiveJob::Base
      include AcidicJob::Workflow

      def unique_by; %w[a b]; end

      def perform; end
    end

    job = AcidicByBlockWithArrayOfStrings.new

    assert_equal "0473ef2dc0d324ab659d3580c1134e9d812035905c4781fdd6d529b0c6860e13", job.idempotency_key
  end

  test "`idempotency_key` when `unique_by` is a first argument returns hexidigest" do
    class AcidicByBlockWithArg < ActiveJob::Base
      include AcidicJob::Workflow

      def unique_by; arguments[0]; end

      def perform; end
    end

    job = AcidicByBlockWithArg.new("a")

    assert_equal "ac8d8342bbb2362d13f0a559a3621bb407011368895164b628a54f7fc33fc43c", job.idempotency_key
  end

  test "`idempotency_key` when `unique_by` is value of first argument returns hexidigest" do
    class AcidicByBlockWithArgValue < ActiveJob::Base
      include AcidicJob::Workflow

      def unique_by
        item = arguments.first[:a]
        item.value
      end

      def perform; end
    end

    job = AcidicByBlockWithArgValue.new(a: Struct.new(:value).new("a"))

    assert_equal "ac8d8342bbb2362d13f0a559a3621bb407011368895164b628a54f7fc33fc43c", job.idempotency_key
  end
end
