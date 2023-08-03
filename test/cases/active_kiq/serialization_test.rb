# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require "acidic_job/active_kiq"

module Cases
  module ActiveKiq
    class Serialization < ActiveSupport::TestCase
      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
        Sidekiq::Queues.clear_all
        Sidekiq.redis(&:flushdb)
      end

      class SerializableWorker < AcidicJob::ActiveKiq
        sidekiq_options queue: "some_queue", retry_queue: "retry_queue", retry: 5, backtrace: 10, tags: ["alpha", "🥇"]

        def perform(required_positional, optional_positional = "OPTIONAL POSITIONAL", *splat_args); end
      end

      test "serializes full job info without any options or arguments" do
        serialized_job = SerializableWorker.new.serialize

        assert_equal [self.class.name, "SerializableWorker"].join("::"), serialized_job["job_class"]
        assert_empty serialized_job["arguments"]
        assert_equal "some_queue", serialized_job["queue_name"]
        assert_equal 5, serialized_job["retry"]
        assert_equal "retry_queue", serialized_job["retry_queue"]
        assert_equal 10, serialized_job["backtrace"]
        assert_equal ["alpha", "🥇"], serialized_job["tags"]
      end

      test "serializes full job info without options but with one argument" do
        serialized_job = SerializableWorker.new("required positional argument").serialize

        assert_equal [self.class.name, "SerializableWorker"].join("::"), serialized_job["job_class"]
        assert_equal ["required positional argument"], serialized_job["arguments"]
        assert_equal "some_queue", serialized_job["queue_name"]
        assert_equal 5, serialized_job["retry"]
        assert_equal "retry_queue", serialized_job["retry_queue"]
        assert_equal 10, serialized_job["backtrace"]
        assert_equal ["alpha", "🥇"], serialized_job["tags"]
      end

      test "serializes full job info without options but with multiple arguments" do
        serialized_job = SerializableWorker.new("required positional argument",
                                                "optional positional argument").serialize

        assert_equal [self.class.name, "SerializableWorker"].join("::"), serialized_job["job_class"]
        assert_equal ["required positional argument", "optional positional argument"], serialized_job["arguments"]
        assert_equal "some_queue", serialized_job["queue_name"]
        assert_equal 5, serialized_job["retry"]
        assert_equal "retry_queue", serialized_job["retry_queue"]
        assert_equal 10, serialized_job["backtrace"]
        assert_equal ["alpha", "🥇"], serialized_job["tags"]
      end
    end
  end
end
