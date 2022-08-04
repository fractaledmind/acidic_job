# frozen_string_literal: true

require "active_support/test_case"

class TestCase < ActiveSupport::TestCase
  def before_setup
    super
    clear_models
  end

  def after_teardown
    clear_models
    super
  end

  private

  def clear_models
    # for some reason DatabaseCleaner wasn't working for various Rails versions :shrug:
    Audit.delete_all
    Ride.delete_all
    Notification.delete_all
    User.delete_all
    AcidicJob::Run.delete_all
  end
end
