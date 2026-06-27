# frozen_string_literal: true

require "test_helper"

class AcidicJob::MailMessageSerializerTest < ActiveJob::TestCase
  def setup
    require "acidic_job/serializers/mail_message_serializer"
    @serializer = AcidicJob::Serializers::MailMessageSerializer.instance
  end

  test "serialize? returns true for a Mail::Message" do
    assert @serializer.serialize?(TestMailer.hello_world.message)
  end

  test "serialize? returns false for non-Mail objects" do
    assert_not @serializer.serialize?("string")
    assert_not @serializer.serialize?(123)
  end

  test "serializes a Mail::Message to a deflated yaml hash" do
    serialized = @serializer.serialize(TestMailer.hello_world.message)

    assert serialized.key?("_aj_serialized")
    assert serialized.key?("deflated_yaml")
    assert_instance_of String, serialized["deflated_yaml"]
  end

  test "round-trips a Mail::Message" do
    mail = TestMailer.hello_world.message

    serialized = @serializer.serialize(mail)
    deserialized = @serializer.deserialize(serialized)

    assert_instance_of ::Mail::Message, deserialized
    assert_equal mail.subject, deserialized.subject
    assert_equal mail.to, deserialized.to
    assert_equal mail.from, deserialized.from
    assert_equal mail.body.to_s, deserialized.body.to_s
  end
end

class AcidicJob::MessageDeliverySerializerTest < ActiveJob::TestCase
  def setup
    require "acidic_job/serializers/message_delivery_serializer"
    @serializer = AcidicJob::Serializers::MessageDeliverySerializer.instance
  end

  test "serialize? returns true for an ActionMailer::MessageDelivery" do
    assert @serializer.serialize?(TestMailer.hello_world)
  end

  test "serialize? returns false for non-MessageDelivery objects" do
    assert_not @serializer.serialize?("string")
    assert_not @serializer.serialize?(TestMailer.hello_world.message)
  end

  test "serializes a MessageDelivery to its mailer class, action, and args" do
    serialized = @serializer.serialize(TestMailer.hello_world)

    assert serialized.key?("_aj_serialized")
    assert_equal "TestMailer", serialized["mailer_class"]
    assert_equal "hello_world", serialized["action"].to_s
    assert_equal [], serialized["args"]
  end

  test "round-trips a MessageDelivery into an equivalent delivery" do
    delivery = TestMailer.hello_world

    serialized = @serializer.serialize(delivery)
    deserialized = @serializer.deserialize(serialized)

    assert_instance_of ::ActionMailer::MessageDelivery, deserialized
    assert_equal delivery.message.subject, deserialized.message.subject
    assert_equal delivery.message.to, deserialized.message.to
    assert_equal delivery.message.body.to_s, deserialized.message.body.to_s
  end
end
