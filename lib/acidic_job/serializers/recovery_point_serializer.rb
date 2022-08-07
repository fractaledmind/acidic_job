# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class RecoveryPointSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(recovery_point)
        super(
          "class" => recovery_point.class.name,
          "name" => recovery_point.name
        )
      end

      def deserialize(hash)
        recovery_point_class = hash["class"].constantize
        recovery_point_class.new(hash["name"])
      end

      def serialize?(argument)
        defined?(::AcidicJob::RecoveryPoint) && argument.is_a?(::AcidicJob::RecoveryPoint)
      end
    end
  end
end
