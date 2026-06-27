# frozen_string_literal: true

require "active_job/serializers/object_serializer"
require "zlib"
require "yaml"

module AcidicJob
  module Serializers
    class ExceptionSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(exception)
        yaml_str = exception.to_yaml
        deflated_binary = Zlib::Deflate.deflate(yaml_str)
        deflated_hex = deflated_binary.unpack1("H*")

        super("deflated_yaml" => deflated_hex)
      end

      def deserialize(hash)
        deflated_binary = [ hash["deflated_yaml"] ].pack("H*")
        yaml_str = Zlib::Inflate.inflate(deflated_binary)

        if YAML.respond_to?(:unsafe_load)
          YAML.unsafe_load(yaml_str)
        else
          YAML.load(yaml_str) # rubocop:disable Security/YAMLLoad
        end
      end

      def serialize?(argument)
        defined?(Exception) && argument.is_a?(Exception)
      end

      def klass
        ::Exception
      end
    end
  end
end
