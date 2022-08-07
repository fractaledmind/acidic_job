# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class ExceptionSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(exception)
        hash = {
          "class" => exception.class.name,
          "message" => exception.message,
          "cause" => exception.cause,
          "backtrace" => {}
        }

        exception.backtrace.map do |trace|
          path, _, location = trace.rpartition("/")

          next if hash["backtrace"].key?(path)

          hash["backtrace"][path] = location
        end

        super(hash)
      end

      def deserialize(hash)
        exception_class = hash["class"].constantize
        exception = exception_class.new(hash["message"])
        exception.set_backtrace(hash["backtrace"].map do |path, location|
          [path, location].join("/")
        end)
        exception
      end

      def serialize?(argument)
        defined?(Exception) && argument.is_a?(Exception)
      end
    end
  end
end
