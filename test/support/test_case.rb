# frozen_string_literal: true

require "active_support/test_case"

class TestCase < ActiveSupport::TestCase
  def before_setup
    super
    clear_models
    clear_sidekiq
  end

  def after_teardown
    clear_models
    clear_sidekiq
    super
  end

  private

  def clear_sidekiq
    return unless defined?(Sidekiq)

    Sidekiq::Queues.clear_all
    Sidekiq.redis(&:flushdb)
  end

  def clear_models
    # for some reason DatabaseCleaner wasn't working for various Rails versions :shrug:
    Audit.delete_all
    Ride.delete_all
    Notification.delete_all
    User.delete_all
    AcidicJob::Run.delete_all
  end
end
