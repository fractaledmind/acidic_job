# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class MessageDeliverySerializer < ::ActiveJob::Serializers::ObjectSerializer
      def serialize(msg_delivery)
        super(
          "mailer_class" => msg_delivery.instance_variable_get(:@mailer_class).name,
          "action" => msg_delivery.instance_variable_get(:@action),
          "args" => msg_delivery.instance_variable_get(:@args)
        )
      end

      def deserialize(hash)
        ActionMailer::MessageDelivery.new(
          hash["mailer_class"].constantize,
          hash["action"],
          *hash["args"]
        )
      end

      def serialize?(argument)
        defined?(::ActionMailer::MessageDelivery) && argument.is_a?(::ActionMailer::MessageDelivery)
      end
    end
  end
end
