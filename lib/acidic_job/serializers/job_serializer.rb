# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class JobSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(job)
        # don't serialize the `enqueued_at` value, as ActiveRecord will check if the Run record has changed
        # by comparing the deserialized database value with a temporary in-memory generated value.
        # That temporary in-memory generated value can sometimes have an `enqueued_at` value that is 1 second off
        # from the original. In this case, ActiveRecord will think the record has unsaved changes and block the lock.
        super(job.serialize.except("enqueued_at"))
      end

      def deserialize(hash)
        job = ActiveJob::Base.deserialize(hash)
        job.send(:deserialize_arguments_if_needed)
        job
      end

      def serialize?(argument)
        defined?(::ActiveJob::Base) && argument.class < ::ActiveJob::Base
      end
    end
  end
end
