# frozen_string_literal: true

require "test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
class TestAcidicJobSerializer < ActiveSupport::TestCase
  def before_setup
    super()
    AcidicJob::Run.delete_all
    Notification.delete_all
    Performance.reset!
  end

  test "can serialize ActiveRecord model" do
    notice = Notification.create!(recipient_id: 1, recipient_type: "User")
    notice.id = 123
    assert_equal(
      { _aj_globalid: "gid://combustion/Notification/123" }.to_json,
      AcidicJob::Serializer.dump(notice)
    )
  end

  test "can serialize a Job class" do
    class RandomJob < ActiveJob::Base; end

    assert_equal(
      { _aj_serialized: "ActiveJob::Serializers::ModuleSerializer",
        value: "TestAcidicJobSerializer::RandomJob" }.to_json,
      AcidicJob::Serializer.dump(RandomJob)
    )
  end

  test "can serialize a Job instance without arguments" do
    class RandomJobWithoutArgs < ActiveJob::Base; end
    instance = RandomJobWithoutArgs.new
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::JobSerializer",
        job_class: "TestAcidicJobSerializer::RandomJobWithoutArgs",
        job_id: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
        provider_job_id: nil,
        queue_name: "default",
        priority: nil,
        arguments: [],
        executions: 0,
        exception_executions: {},
        locale: "en",
        timezone: "UTC" }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize a Job instance with simple arguments" do
    class RandomJobWithSimpleArgs < ActiveJob::Base; end
    instance = RandomJobWithSimpleArgs.new(123, "string")
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::JobSerializer",
        job_class: "TestAcidicJobSerializer::RandomJobWithSimpleArgs",
        job_id: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
        provider_job_id: nil,
        queue_name: "default",
        priority: nil,
        arguments: [123, "string"],
        executions: 0,
        exception_executions: {},
        locale: "en",
        timezone: "UTC" }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize a Job instance with ActiveRecord model argument" do
    class RandomJobWithModelArg < ActiveJob::Base; end
    notice = Notification.create!(recipient_id: 1, recipient_type: "User")
    notice.id = 456
    instance = RandomJobWithModelArg.new(notice)
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::JobSerializer",
        job_class: "TestAcidicJobSerializer::RandomJobWithModelArg",
        job_id: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
        provider_job_id: nil,
        queue_name: "default",
        priority: nil,
        arguments: [{ _aj_globalid: "gid://combustion/Notification/456" }],
        executions: 0,
        exception_executions: {},
        locale: "en",
        timezone: "UTC" }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize a Job instance with Range argument" do
    class RandomJobWithRangeArg < ActiveJob::Base; end
    instance = RandomJobWithRangeArg.new(1..10)
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    expectation = if Gem::Version.new(Rails.version) >= Gem::Version.new("7.0")
                    { _aj_serialized: "AcidicJob::Serializers::JobSerializer",
                      job_class: "TestAcidicJobSerializer::RandomJobWithRangeArg",
                      job_id: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
                      provider_job_id: nil,
                      queue_name: "default",
                      priority: nil,
                      arguments: [{ _aj_serialized: "ActiveJob::Serializers::RangeSerializer",
                                    begin: 1,
                                    end: 10,
                                    exclude_end: false }],
                      executions: 0,
                      exception_executions: {},
                      locale: "en",
                      timezone: "UTC" }.to_json
                  else
                    { _aj_serialized: "AcidicJob::Serializers::JobSerializer",
                      job_class: "TestAcidicJobSerializer::RandomJobWithRangeArg",
                      job_id: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
                      provider_job_id: nil,
                      queue_name: "default",
                      priority: nil,
                      arguments: [{ _aj_serialized: "AcidicJob::Serializers::RangeSerializer",
                                    begin: 1,
                                    end: 10,
                                    exclude_end: false }],
                      executions: 0,
                      exception_executions: {},
                      locale: "en",
                      timezone: "UTC" }.to_json
                  end

    assert_equal(
      expectation,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize a Job instance with Exception argument" do
    class RandomJobWithExceptionArg < ActiveJob::Base; end
    exception = StandardError.new("CUSTOM MESSAGE")
    exception.set_backtrace([])
    instance = RandomJobWithExceptionArg.new(exception)
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::JobSerializer",
        job_class: "TestAcidicJobSerializer::RandomJobWithExceptionArg",
        job_id: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
        provider_job_id: nil,
        queue_name: "default",
        priority: nil,
        arguments: [{ _aj_serialized: "AcidicJob::Serializers::ExceptionSerializer",
                      yaml: exception.to_yaml }],
        executions: 0,
        exception_executions: {},
        locale: "en",
        timezone: "UTC" }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize a Job instance with FinishedPoint argument" do
    class RandomJobWithFinishedPointArg < ActiveJob::Base; end
    instance = RandomJobWithFinishedPointArg.new(AcidicJob::FinishedPoint.new)
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::JobSerializer",
        job_class: "TestAcidicJobSerializer::RandomJobWithFinishedPointArg",
        job_id: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
        provider_job_id: nil,
        queue_name: "default",
        priority: nil,
        arguments: [{ _aj_serialized: "AcidicJob::Serializers::FinishedPointSerializer",
                      class: "AcidicJob::FinishedPoint" }],
        executions: 0,
        exception_executions: {},
        locale: "en",
        timezone: "UTC" }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize a Job instance with RecoveryPoint argument" do
    class RandomJobWithRecoveryPointArg < ActiveJob::Base; end
    instance = RandomJobWithRecoveryPointArg.new(AcidicJob::RecoveryPoint.new("RECOVERY_POINT"))
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::JobSerializer",
        job_class: "TestAcidicJobSerializer::RandomJobWithRecoveryPointArg",
        job_id: "12a345bc-67e8-90f1-23g4-5h6i7jk8l901",
        provider_job_id: nil,
        queue_name: "default",
        priority: nil,
        arguments: [{ _aj_serialized: "AcidicJob::Serializers::RecoveryPointSerializer",
                      class: "AcidicJob::RecoveryPoint",
                      name: "RECOVERY_POINT" }],
        executions: 0,
        exception_executions: {},
        locale: "en",
        timezone: "UTC" }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize a Worker class" do
    class RandomWorker
      include Sidekiq::Worker
    end

    assert_equal(
      { _aj_serialized: "ActiveJob::Serializers::ModuleSerializer",
        value: "TestAcidicJobSerializer::RandomWorker" }.to_json,
      AcidicJob::Serializer.dump(RandomWorker)
    )
  end

  test "can serialize a Worker instance without arguments" do
    class RandomWorkerWithoutArgs
      include Sidekiq::Worker
    end
    instance = RandomWorkerWithoutArgs.new
    instance.jid = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::WorkerSerializer",
        job_class: "TestAcidicJobSerializer::RandomWorkerWithoutArgs" }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize an ActiveKiq class" do
    class RandomActiveKiq < AcidicJob::ActiveKiq; end

    assert_equal(
      { _aj_serialized: "ActiveJob::Serializers::ModuleSerializer",
        value: "TestAcidicJobSerializer::RandomActiveKiq" }.to_json,
      AcidicJob::Serializer.dump(RandomActiveKiq)
    )
  end

  test "can serialize an ActiveKiq instance without arguments" do
    class RandomActiveKiqWithoutArgs < AcidicJob::ActiveKiq; end
    instance = RandomActiveKiqWithoutArgs.new
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::ActiveKiqSerializer",
        job_class: "TestAcidicJobSerializer::RandomActiveKiqWithoutArgs",
        arguments: [] }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize an ActiveKiq instance with simple arguments" do
    class RandomActiveKiqWithSimpleArgs < AcidicJob::ActiveKiq; end
    instance = RandomActiveKiqWithSimpleArgs.new(123, "string")
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::ActiveKiqSerializer",
        job_class: "TestAcidicJobSerializer::RandomActiveKiqWithSimpleArgs",
        arguments: [123, "string"] }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize an ActiveKiq instance with ActiveRecord model argument" do
    class RandomActiveKiqWithModelArg < AcidicJob::ActiveKiq; end
    notice = Notification.create!(recipient_id: 1, recipient_type: "User")
    notice.id = 456
    instance = RandomActiveKiqWithModelArg.new(notice)
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::ActiveKiqSerializer",
        job_class: "TestAcidicJobSerializer::RandomActiveKiqWithModelArg",
        arguments: [{ _aj_globalid: "gid://combustion/Notification/456" }] }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize an ActiveKiq instance with Range argument" do
    class RandomActiveKiqWithRangeArg < AcidicJob::ActiveKiq; end
    instance = RandomActiveKiqWithRangeArg.new(1..10)
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    expectation = if Gem::Version.new(Rails.version) >= Gem::Version.new("7.0")
                    { _aj_serialized: "AcidicJob::Serializers::ActiveKiqSerializer",
                      job_class: "TestAcidicJobSerializer::RandomActiveKiqWithRangeArg",
                      arguments: [
                        { _aj_serialized: "ActiveJob::Serializers::RangeSerializer", begin: 1, end: 10,
                          exclude_end: false }
                      ] }.to_json
                  else
                    { _aj_serialized: "AcidicJob::Serializers::ActiveKiqSerializer",
                      job_class: "TestAcidicJobSerializer::RandomActiveKiqWithRangeArg",
                      arguments: [
                        { _aj_serialized: "AcidicJob::Serializers::RangeSerializer", begin: 1, end: 10,
                          exclude_end: false }
                      ] }.to_json
                  end

    assert_equal(
      expectation,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize an ActiveKiq instance with Exception argument" do
    class RandomActiveKiqWithExceptionArg < AcidicJob::ActiveKiq; end
    exception = StandardError.new("CUSTOM MESSAGE")
    exception.set_backtrace([])
    instance = RandomActiveKiqWithExceptionArg.new(exception)
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::ActiveKiqSerializer",
        job_class: "TestAcidicJobSerializer::RandomActiveKiqWithExceptionArg",
        arguments: [
          { _aj_serialized: "AcidicJob::Serializers::ExceptionSerializer",
            yaml: exception.to_yaml
          }
        ] }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize an ActiveKiq instance with FinishedPoint argument" do
    class RandomActiveKiqWithFinishedPointArg < AcidicJob::ActiveKiq; end
    instance = RandomActiveKiqWithFinishedPointArg.new(AcidicJob::FinishedPoint.new)
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::ActiveKiqSerializer",
        job_class: "TestAcidicJobSerializer::RandomActiveKiqWithFinishedPointArg",
        arguments: [
          { _aj_serialized: "AcidicJob::Serializers::FinishedPointSerializer", class: "AcidicJob::FinishedPoint" }
        ] }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end

  test "can serialize an ActiveKiq instance with RecoveryPoint argument" do
    class RandomActiveKiqWithRecoveryPointArg < AcidicJob::ActiveKiq; end
    instance = RandomActiveKiqWithRecoveryPointArg.new(AcidicJob::RecoveryPoint.new("RECOVERY_POINT"))
    instance.job_id = "12a345bc-67e8-90f1-23g4-5h6i7jk8l901"

    assert_equal(
      { _aj_serialized: "AcidicJob::Serializers::ActiveKiqSerializer",
        job_class: "TestAcidicJobSerializer::RandomActiveKiqWithRecoveryPointArg",
        arguments: [
          { _aj_serialized: "AcidicJob::Serializers::RecoveryPointSerializer", class: "AcidicJob::RecoveryPoint",
            name: "RECOVERY_POINT" }
        ] }.to_json,
      AcidicJob::Serializer.dump(instance)
    )
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
