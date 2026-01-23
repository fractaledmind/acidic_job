# frozen_string_literal: true

require "test_helper"

class AcidicJob::EngineTest < ActiveSupport::TestCase
  test "engine is a Rails::Engine" do
    assert_kind_of ::Rails::Engine, AcidicJob::Engine.instance
  end

  test "engine isolates AcidicJob namespace" do
    assert_equal "acidic_job", AcidicJob::Engine.engine_name
  end

  test "config.acidic_job is available" do
    assert_respond_to Rails.application.config, :acidic_job
  end

  test "logger can be configured" do
    original_logger = AcidicJob.logger

    custom_logger = Logger.new(IO::NULL)
    AcidicJob.logger = custom_logger

    assert_equal custom_logger, AcidicJob.logger
  ensure
    AcidicJob.logger = original_logger
  end

  test "LogSubscriber responds to acidic_job events" do
    subscriber = AcidicJob::LogSubscriber.new

    # These are the events the LogSubscriber should handle
    assert_respond_to subscriber, :define_workflow
    assert_respond_to subscriber, :initialize_workflow
    assert_respond_to subscriber, :process_workflow
    assert_respond_to subscriber, :process_step
    assert_respond_to subscriber, :perform_step
  end

  test "custom serializers are registered" do
    serializers = ActiveJob::Serializers.serializers

    # Check our custom serializers are registered
    serializer_classes = serializers.map(&:class)

    assert_includes serializer_classes, AcidicJob::Serializers::ExceptionSerializer
    assert_includes serializer_classes, AcidicJob::Serializers::NewRecordSerializer
    assert_includes serializer_classes, AcidicJob::Serializers::JobSerializer
  end

  test "ExceptionSerializer can serialize and deserialize exceptions" do
    original = StandardError.new("test message")

    serialized = ActiveJob::Serializers.serialize(original)
    deserialized = ActiveJob::Serializers.deserialize(serialized)

    assert_kind_of StandardError, deserialized
    assert_equal "test message", deserialized.message
  end

  test "JobSerializer can serialize and deserialize jobs" do
    job = DoingJob.new

    serialized = ActiveJob::Serializers.serialize(job)
    deserialized = ActiveJob::Serializers.deserialize(serialized)

    assert_kind_of DoingJob, deserialized
    assert_equal job.job_id, deserialized.job_id
  end

  test "NewRecordSerializer can serialize and deserialize unpersisted records" do
    original = Thing.new

    serialized = ActiveJob::Serializers.serialize(original)
    deserialized = ActiveJob::Serializers.deserialize(serialized)

    assert_kind_of Thing, deserialized
    assert deserialized.new_record?
  end
end
