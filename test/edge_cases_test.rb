# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"

class TestWorker
  include Sidekiq::Worker
  include AcidicJob

  def perform(some_id)
    idempotently with: { some_id: some_id } do
      step :do_something
    end
  rescue StandardError
    true
  end

  def do_something
    raise StandardError
  end
end

class TestEdgeCases < Minitest::Test
  def before_setup
    super
    DatabaseCleaner.start
    Sidekiq::Queues.clear_all
  end

  def after_teardown
    Sidekiq::Queues.clear_all
    DatabaseCleaner.clean
    super
  end

  def test_error_in_first_step_rolls_back_step_transaction
    TestWorker.new.perform(1)

    assert_equal 1, AcidicJob::Key.count
    assert_equal StandardError, AcidicJob::Key.first.error_object.class
  end
end
