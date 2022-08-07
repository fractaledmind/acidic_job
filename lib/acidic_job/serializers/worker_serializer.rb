# frozen_string_literal: true

require "active_job/serializers/object_serializer"

# :nocov:
module AcidicJob
  module Serializers
    class WorkerSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(worker)
        super(
          "job_class" => worker.class.name,
          "arguments" => worker.arguments,
        )
      end

      def deserialize(hash)
        worker_class = hash["job_class"].constantize
        worker_class.new(*hash["arguments"])
      end

      def serialize?(argument)
        defined?(::Sidekiq) && argument.class.include?(::Sidekiq::Worker)
      end
    end
  end
end
# :nocov:
