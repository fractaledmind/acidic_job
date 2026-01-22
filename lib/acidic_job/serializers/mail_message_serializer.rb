# frozen_string_literal: true

require "active_job/serializers/object_serializer"
require "zlib"
require "yaml"

module AcidicJob
  module Serializers
    class MailMessageSerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(mail_msg)
        yaml_str = mail_msg.to_yaml
        deflated_binary = Zlib::Deflate.deflate(yaml_str)
        deflated_hex = deflated_binary.unpack("H*")

        super("deflated_yaml" => deflated_hex)
      end

      def deserialize(hash)
        deflated_binary = hash["deflated_yaml"].pack("H*")
        yaml_str = Zlib::Inflate.inflate(deflated_binary)

        Mail::Message.from_yaml(yaml_str)
      end

      def serialize?(argument)
        defined?(Mail::Message) && argument.is_a?(Mail::Message)
      end
    end
  end
end
