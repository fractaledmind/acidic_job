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

        super({ "yaml" => exception.to_yaml })
      end

      def deserialize(hash)
        if hash.key?("class")
          exception_class = hash["class"].constantize
          exception = exception_class.new(hash["message"])
          exception.set_backtrace(hash["backtrace"].map do |path, location|
                                    [path, location].join("/")
                                  end)
          exception
        elsif hash.key?("yaml")
          if YAML.respond_to?(:unsafe_load)
            YAML.unsafe_load(hash["yaml"])
          else
            YAML.load(hash["yaml"]) # rubocop:disable Security/YAMLLoad
          end
        end
      end

      def serialize?(argument)
        defined?(Exception) && argument.is_a?(Exception)
      end
    end
  end
end
