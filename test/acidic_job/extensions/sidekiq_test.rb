# frozen_string_literal: true

require "test_helper"
require "acidic_job/test_case"
require "sidekiq"
require "sidekiq/testing"

class ExampleWorker
  include Sidekiq::Worker
  include AcidicJob

  def perform; end
end

class TestSidekiqExtension < AcidicJob::TestCase
  def test_perform_acidicly_with_unique_by
    ExampleWorker.perform_acidicly(unique_by: { key: "value" })

    assert_equal 1, AcidicJob::Run.staged.count

    worker_run = AcidicJob::Run.staged.first
    assert_equal "bb061e8599507b55357c5388562d49a5d74de19f", worker_run.idempotency_key
  end
end
