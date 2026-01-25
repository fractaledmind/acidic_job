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

  test "RangeSerializer is only registered when Rails does not provide one" do
    serializers = ActiveJob::Serializers.serializers
    has_rails_range_serializer = defined?(ActiveJob::Serializers::RangeSerializer)

    # Check if AcidicJob's RangeSerializer is registered (not just defined, since tests may load it)
    acidic_range_serializer_registered = defined?(AcidicJob::Serializers::RangeSerializer) &&
                                         serializers.any? { |s| s.is_a?(AcidicJob::Serializers::RangeSerializer) }

    if has_rails_range_serializer
      # When Rails provides RangeSerializer, AcidicJob's should not be registered
      assert_not acidic_range_serializer_registered,
                 "AcidicJob::RangeSerializer should not be registered when Rails provides one"
    else
      # When Rails doesn't provide RangeSerializer, AcidicJob's should be registered
      assert acidic_range_serializer_registered,
             "AcidicJob::RangeSerializer should be registered when Rails does not provide one"
    end
  end
end

class AcidicJob::RangeSerializerTest < ActiveJob::TestCase
  # Test the RangeSerializer directly, regardless of whether it's registered
  def setup
    require "acidic_job/serializers/range_serializer"
    @serializer = AcidicJob::Serializers::RangeSerializer.instance
  end

  test "RangeSerializer has public klass method returning Range" do
    assert_equal ::Range, @serializer.klass
  end

  test "RangeSerializer serializes inclusive range" do
    range = 1..10

    assert @serializer.serialize?(range)

    serialized = @serializer.serialize(range)
    assert serialized.key?("_aj_serialized")
    assert serialized.key?("begin")
    assert serialized.key?("end")
    assert serialized.key?("exclude_end")
    assert_equal 1, serialized["begin"]
    assert_equal 10, serialized["end"]
    assert_equal false, serialized["exclude_end"]
  end

  test "RangeSerializer serializes exclusive range" do
    range = 1...10

    serialized = @serializer.serialize(range)
    assert_equal true, serialized["exclude_end"]
  end

  test "RangeSerializer deserializes inclusive range" do
    range = 1..10

    serialized = @serializer.serialize(range)
    deserialized = @serializer.deserialize(serialized)

    assert_instance_of Range, deserialized
    assert_equal 1, deserialized.begin
    assert_equal 10, deserialized.end
    assert_not deserialized.exclude_end?
  end

  test "RangeSerializer deserializes exclusive range" do
    range = 1...10

    serialized = @serializer.serialize(range)
    deserialized = @serializer.deserialize(serialized)

    assert_instance_of Range, deserialized
    assert deserialized.exclude_end?
  end

  test "RangeSerializer round-trips string ranges" do
    range = "a".."z"

    serialized = @serializer.serialize(range)
    deserialized = @serializer.deserialize(serialized)

    assert_equal range, deserialized
  end

  test "RangeSerializer round-trips beginless range" do
    range = (..10)

    serialized = @serializer.serialize(range)
    deserialized = @serializer.deserialize(serialized)

    assert_equal range, deserialized
    assert_nil deserialized.begin
  end

  test "RangeSerializer round-trips endless range" do
    range = (1..)

    serialized = @serializer.serialize(range)
    deserialized = @serializer.deserialize(serialized)

    assert_equal range, deserialized
    assert_nil deserialized.end
  end
end
