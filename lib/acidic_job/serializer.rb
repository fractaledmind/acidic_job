# frozen_string_literal: true

require "json"
require_relative "arguments"

module AcidicJob
  # Used for `serialize` method in ActiveRecord
  module Serializer
    extend self

    def load(json)
      return if json.nil? || json.empty?

      data = JSON.parse json

      Arguments.__send__ :deserialize_argument, data
    end

    def dump(obj)
      data = Arguments.__send__ :serialize_argument, obj

      JSON.generate data, strict: true
    rescue ActiveJob::SerializationError => e
      e.message << " (`#{obj.inspect}`)"
      raise e
    end
  end
end
