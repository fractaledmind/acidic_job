# frozen_string_literal: true

require "test_helper"

class AcidicJob::SerializersTest < ActiveJob::TestCase
  # Helper method to get the singleton serializer instance
  def get_serializer(klass)
    ActiveJob::Serializers.serializers.find { |s| s.is_a?(klass) }
  end

  test "ExceptionSerializer has public klass method returning Exception" do
    serializer = get_serializer(AcidicJob::Serializers::ExceptionSerializer)
    assert_equal ::Exception, serializer.klass
  end

  test "ExceptionSerializer serializes StandardError" do
    serializer = get_serializer(AcidicJob::Serializers::ExceptionSerializer)
    error = StandardError.new("test error")
    error.set_backtrace([ "line 1", "line 2" ])

    assert serializer.serialize?(error)

    serialized = serializer.serialize(error)
    assert serialized.key?("_aj_serialized")
    assert serialized.key?("deflated_yaml")
    assert_instance_of String, serialized["deflated_yaml"]
  end

  test "ExceptionSerializer deserializes StandardError" do
    serializer = get_serializer(AcidicJob::Serializers::ExceptionSerializer)
    original_error = StandardError.new("test error message")
    original_error.set_backtrace([ "line 1", "line 2" ])

    serialized = serializer.serialize(original_error)
    deserialized = serializer.deserialize(serialized)

    assert_instance_of StandardError, deserialized
    assert_equal "test error message", deserialized.message
    assert_equal [ "line 1", "line 2" ], deserialized.backtrace
  end

  test "ExceptionSerializer round-trips custom exceptions" do
    serializer = get_serializer(AcidicJob::Serializers::ExceptionSerializer)
    original_error = DefaultsError.new("custom error")

    serialized = serializer.serialize(original_error)
    deserialized = serializer.deserialize(serialized)

    assert_instance_of DefaultsError, deserialized
    assert_equal "custom error", deserialized.message
  end

  test "JobSerializer has public klass method returning ActiveJob::Base" do
    serializer = get_serializer(AcidicJob::Serializers::JobSerializer)
    assert_equal ::ActiveJob::Base, serializer.klass
  end

  test "JobSerializer serializes ActiveJob instances" do
    serializer = get_serializer(AcidicJob::Serializers::JobSerializer)
    job = DoingJob.new("test_arg")

    assert serializer.serialize?(job)

    serialized = serializer.serialize(job)
    assert serialized.key?("_aj_serialized")
    assert serialized.key?("job_class")
    assert_equal "DoingJob", serialized["job_class"]
  end

  test "JobSerializer excludes enqueued_at from serialization" do
    serializer = get_serializer(AcidicJob::Serializers::JobSerializer)
    job = DoingJob.new("test_arg")
    job.enqueued_at = Time.current

    serialized = serializer.serialize(job)
    assert_not serialized.key?("enqueued_at"), "enqueued_at should not be serialized"
  end

  test "JobSerializer deserializes ActiveJob instances" do
    serializer = get_serializer(AcidicJob::Serializers::JobSerializer)
    original_job = DoingJob.new("test_arg", 42)

    serialized = serializer.serialize(original_job)
    deserialized = serializer.deserialize(serialized)

    assert_instance_of DoingJob, deserialized
    assert_equal [ "test_arg", 42 ], deserialized.arguments
  end

  test "JobSerializer round-trips jobs with various argument types" do
    serializer = get_serializer(AcidicJob::Serializers::JobSerializer)
    original_job = DoingJob.new("string", 123, { key: "value" }, [ 1, 2, 3 ])

    serialized = serializer.serialize(original_job)
    deserialized = serializer.deserialize(serialized)

    assert_equal original_job.arguments, deserialized.arguments
  end

  test "NewRecordSerializer has public klass method returning ActiveRecord::Base" do
    serializer = get_serializer(AcidicJob::Serializers::NewRecordSerializer)
    assert_equal ::ActiveRecord::Base, serializer.klass
  end

  test "NewRecordSerializer serializes new ActiveRecord instances" do
    serializer = get_serializer(AcidicJob::Serializers::NewRecordSerializer)
    new_thing = Thing.new

    assert serializer.serialize?(new_thing)

    serialized = serializer.serialize(new_thing)
    assert serialized.key?("_aj_serialized")
    assert serialized.key?("class")
    assert serialized.key?("attributes")
    assert_equal "Thing", serialized["class"]
  end

  test "NewRecordSerializer deserializes new ActiveRecord instances" do
    serializer = get_serializer(AcidicJob::Serializers::NewRecordSerializer)
    new_thing = Thing.new

    serialized = serializer.serialize(new_thing)
    deserialized = serializer.deserialize(serialized)

    assert_instance_of Thing, deserialized
    assert_predicate deserialized, :new_record?
  end

  test "NewRecordSerializer serialize? returns true for new records" do
    serializer = get_serializer(AcidicJob::Serializers::NewRecordSerializer)
    new_thing = Thing.new

    assert serializer.serialize?(new_thing)
  end

  test "NewRecordSerializer serialize? returns false for persisted records" do
    serializer = get_serializer(AcidicJob::Serializers::NewRecordSerializer)
    persisted_thing = Thing.create!

    assert_not serializer.serialize?(persisted_thing)
  end

  test "NewRecordSerializer serialize? returns false for non-record objects" do
    serializer = get_serializer(AcidicJob::Serializers::NewRecordSerializer)

    assert_not serializer.serialize?("string")
    assert_not serializer.serialize?(123)
    assert_not serializer.serialize?(Object.new)
  end

  test "all serializers are registered with ActiveJob" do
    serializers = ActiveJob::Serializers.serializers

    assert serializers.any? { |s| s.is_a?(AcidicJob::Serializers::ExceptionSerializer) },
           "ExceptionSerializer should be registered"

    assert serializers.any? { |s| s.is_a?(AcidicJob::Serializers::JobSerializer) },
           "JobSerializer should be registered"

    assert serializers.any? { |s| s.is_a?(AcidicJob::Serializers::NewRecordSerializer) },
           "NewRecordSerializer should be registered"
  end
end
