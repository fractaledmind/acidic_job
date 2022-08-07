# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class FinishedPointSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(finished_point)
        super(
          "class" => finished_point.class.name
        )
      end

      def deserialize(hash)
        finished_point_class = hash["class"].constantize
        finished_point_class.new
      end

      def serialize?(argument)
        defined?(::AcidicJob::FinishedPoint) && argument.is_a?(::AcidicJob::FinishedPoint)
      end
    end
  end
end
