# frozen_string_literal: true

require "json"

module AcidicJob
  class Serializer
    # Used for `serialize` method in ActiveRecord
    class << self
      def load(json)
        return if json.nil? || json.empty?

        data = JSON.parse(json)
        Arguments.send :deserialize_argument, data
      end

      def dump(obj)
        data = Arguments.send :serialize_argument, obj
        data.to_json
      rescue ActiveJob::SerializationError
        raise UnserializableValue
      end
    end
  end
end
