# frozen_string_literal: true

require "test_helper"
require "noticed"
require "active_job"
require_relative "../../support/test_case"

Noticed.parent_class = "ActiveJob::Base"
Noticed::Base.include AcidicJob::Extensions::Noticed

class OnlyDatabaseNotification < Noticed::Base
  deliver_by :database
end

class ExampleNotification < Noticed::Base
  deliver_by :database
  deliver_by :test, foo: :bar
end

class TestNoticedExtension < TestCase
  def setup
    @user = User.find_or_create_by(email: "user@example.com", stripe_customer_id: "tok_visa")
  end

  def test_deliver_acidicly_on_noticed_notification_with_only_database_delivery
    OnlyDatabaseNotification.deliver_acidicly(@user)

    assert_equal 0, AcidicJob::Run.staged.count
  end

  def test_deliver_acidicly_on_noticed_notification_with_other_deliveries
    ExampleNotification.deliver_acidicly(@user)

    assert_equal 1, AcidicJob::Run.staged.count

    noticed_run = AcidicJob::Run.staged.first
    assert_equal "Noticed::DeliveryMethods::Test", noticed_run.job_class
    assert_equal "default", noticed_run.serialized_job["queue_name"]
  end

  def test_deliver
    dynamic_class = Class.new(ActiveJob::Base) do
      include AcidicJob
    end
    Object.const_set("AppJob", dynamic_class)
    Noticed.parent_class = "AppJob"

    delivered_to = OnlyDatabaseNotification.with({}).deliver(@user)

    assert_equal [@user], delivered_to
  end
end
