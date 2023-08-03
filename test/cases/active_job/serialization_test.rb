# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

module Cases
  module ActiveJob
    class Serialization < ActiveSupport::TestCase
      include ::ActiveJob::TestHelper

      def before_setup
        super()
        AcidicJob::Run.delete_all
        Notification.delete_all
        Performance.reset!
      end

      class SerializableJob < AcidicJob::Base
        queue_as :some_queue
        self.queue_name_prefix = :test
        self.queue_name_delimiter = "_"
        queue_with_priority 50
        retry_on StandardError, attempts: 5

        def perform(required_positional, optional_positional = "OPTIONAL POSITIONAL", *splat_args); end
      end

      # {
      #   "job_class"=>"...::SerializableJob",
      #   "job_id"=>"1e84f61e-1725-43b3-9a23-a358b9646e52",
      #   "provider_job_id"=>nil,
      #   "queue_name"=>"some_queue",
      #   "priority"=>50,
      #   "arguments"=>[],
      #   "executions"=>0,
      #   "exception_executions"=>{},
      #   "locale"=>"en",
      #   "timezone"=>"UTC",
      #   "enqueued_at"=>"2022-08-07T17:47:24Z"
      # }

      test "serializes full job info without any options or arguments" do
        serialized_job = SerializableJob.new.serialize

        assert_equal [self.class.name, "SerializableJob"].join("::"), serialized_job["job_class"]
        assert_empty serialized_job["arguments"]
        assert_equal "some_queue", serialized_job["queue_name"]
        assert_equal 50, serialized_job["priority"]
        assert_equal "en", serialized_job["locale"]
        assert_equal "UTC", serialized_job["timezone"]
      end

      test "serializes full job info without options but with one argument" do
        serialized_job = SerializableJob.new("required positional argument").serialize

        assert_equal [self.class.name, "SerializableJob"].join("::"), serialized_job["job_class"]
        assert_equal ["required positional argument"], serialized_job["arguments"]
        assert_equal "some_queue", serialized_job["queue_name"]
        assert_equal 50, serialized_job["priority"]
        assert_equal "en", serialized_job["locale"]
        assert_equal "UTC", serialized_job["timezone"]
      end

      test "serializes full job info without options but with multiple arguments" do
        serialized_job = SerializableJob.new("required positional argument", "optional positional argument").serialize

        assert_equal [self.class.name, "SerializableJob"].join("::"), serialized_job["job_class"]
        assert_equal ["required positional argument", "optional positional argument"], serialized_job["arguments"]
        assert_equal "some_queue", serialized_job["queue_name"]
        assert_equal 50, serialized_job["priority"]
        assert_equal "en", serialized_job["locale"]
        assert_equal "UTC", serialized_job["timezone"]
      end
    end
  end
end
