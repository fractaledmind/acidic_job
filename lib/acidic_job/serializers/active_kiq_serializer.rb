# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class ActiveKiqSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(worker)
        super(
          "job_class" => worker.class.name,
          "arguments" => Arguments.serialize(worker.arguments),
        )
      end

      def deserialize(hash)
        worker_class = hash["job_class"].constantize
        worker_class.new(*hash["arguments"])
      end

      def serialize?(argument)
        defined?(::AcidicJob::ActiveKiq) && argument.class < ::AcidicJob::ActiveKiq
      end
    end
  end
end
