# frozen_string_literal: true

require "test_helper"

ActionMailer::MessageDelivery.include AcidicJob::Extensions::ActionMailer
ActionMailer::Parameterized::MessageDelivery.include AcidicJob::Extensions::ActionMailer

class UserMailer < ActionMailer::Base
  def comment_notification
    mail(body: "")
  end
end

class TestActionMailerExtension < Minitest::Test
  def setup
    @user = User.find_or_create_by(email: "user@example.com", stripe_customer_id: "tok_visa")
  end

  def before_setup
    super
    DatabaseCleaner.start
  end

  def after_teardown
    DatabaseCleaner.clean
    super
  end

  def test_deliver_acidicly_on_parameterized_action_mailer
    UserMailer.with({}).comment_notification.deliver_acidicly

    assert_equal 1, AcidicJob::Run.staged.count

    mailer_run = AcidicJob::Run.staged.first
    assert_equal "ActionMailer::MailDeliveryJob", mailer_run.job_class
    assert_equal "mailers", mailer_run.serialized_job["queue_name"]
  end

  def test_deliver_acidicly_on_action_mailer
    UserMailer.comment_notification.deliver_acidicly

    assert_equal 1, AcidicJob::Run.staged.count

    mailer_run = AcidicJob::Run.staged.first
    assert_equal "ActionMailer::MailDeliveryJob", mailer_run.job_class
    assert_equal "mailers", mailer_run.serialized_job["queue_name"]
  end
end
