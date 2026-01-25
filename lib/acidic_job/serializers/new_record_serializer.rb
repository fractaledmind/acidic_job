# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class NewRecordSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(new_record)
        super(
          "class" => new_record.class.name,
          "attributes" => new_record.attributes
        )
      end

      def deserialize(hash)
        new_record_class = hash["class"].constantize
        new_record_class.new(hash["attributes"])
      end

      def serialize?(argument)
        defined?(::ActiveRecord) && argument.respond_to?(:new_record?) && argument.new_record?
      end

      def klass
        ::ActiveRecord::Base
      end
    end
  end
end
