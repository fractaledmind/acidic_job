# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class ExceptionSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(exception)
        compressed_backtrace = {}
        exception.backtrace&.map do |trace|
          path, _, location = trace.rpartition("/")
          next if compressed_backtrace.key?(path)
          compressed_backtrace[path] = location
        end
        exception.set_backtrace(compressed_backtrace.map do |path, location|
          [path, location].join("/")
        end)
        exception.cause&.set_backtrace([])

        super({'yaml' => exception.to_yaml})
      end

      def deserialize(hash)
        exception = YAML.unsafe_load(hash['yaml'])
        
        exception
      end

      def serialize?(argument)
        defined?(Exception) && argument.is_a?(Exception)
      end
    end
  end
end
