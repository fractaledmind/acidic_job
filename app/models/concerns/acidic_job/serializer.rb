# frozen_string_literal: true

require "oj"

module AcidicJob
  class Serializer
    def self.dump(obj)
      data = AcidicJob::Arguments.send :serialize_argument, obj
      Oj.dump(data)
    end

    def self.load(json)
      return {} if json.nil?
      data = Oj.load(json)
      AcidicJob::Arguments.send :deserialize_argument, data
    end
  end
end
