# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class JobSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(job)
        super(job.serialize)
      end

      def deserialize(hash)
        job = ActiveJob::Base.deserialize(hash)
        job.send(:deserialize_arguments_if_needed)
        # this is a shim to ensure we can work with Ruby 2.7 as well as 3.0+
        # :nocov:
        if job.arguments.last.is_a?(Hash)
          *args, kwargs = job.arguments
        else
          args = job.arguments
          kwargs = {}
        end
        # :nocov:
        job.instance_variable_set(:@__acidic_job_args, args)
        job.instance_variable_set(:@__acidic_job_kwargs, kwargs)

        job
      end

      def serialize?(argument)
        defined?(::ActiveJob::Base) && argument.class < ::ActiveJob::Base
      end
    end
  end
end
