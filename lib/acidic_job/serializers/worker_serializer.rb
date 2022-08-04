# frozen_string_literal: true

require "active_job/serializers/object_serializer"

# :nocov:
module AcidicJob
  module Serializers
    class WorkerSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(worker)
        super(
          "class" => worker.class.name,
          "args" => worker.instance_variable_get(:@__acidic_job_args),
          "kwargs" => worker.instance_variable_get(:@__acidic_job_kwargs)
        )
      end

      def deserialize(hash)
        worker_class = hash["class"].constantize
        worker_class.new(*hash["args"], **hash["kwargs"])
      end

      def serialize?(argument)
        defined?(::Sidekiq) && argument.class.include?(::Sidekiq::Worker)
      end
    end
  end
end
# :nocov:
