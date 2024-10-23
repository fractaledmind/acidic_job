# frozen_string_literal: true

require "active_job/serializers/object_serializer"
require "zlib"
require "yaml"

module AcidicJob
  module Serializers
    class ExceptionSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(exception)
       compressed = Zlib::Deflate.deflate(exception.to_yaml)

        super("deflated_yaml" => compressed)
      end

      def deserialize(hash)
        uncompressed = Zlib::Inflate.inflate(hash["deflated_yaml"])

        if YAML.respond_to?(:unsafe_load)
          YAML.unsafe_load(uncompressed)
        else
          YAML.load(uncompressed) # rubocop:disable Security/YAMLLoad
        end
      end

      def serialize?(argument)
        defined?(Exception) && argument.is_a?(Exception)
      end
    end
  end
end
