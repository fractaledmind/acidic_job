# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    class RangeSerializer < ::ActiveJob::Serializers::ObjectSerializer
      KEYS = %w[begin end exclude_end].freeze

      def serialize(range)
        args = Arguments.serialize([range.begin, range.end, range.exclude_end?])
        super(KEYS.zip(args).to_h)
      end

      def deserialize(hash)
        klass.new(*Arguments.deserialize(hash.values_at(*KEYS)))
      end

      private

      def klass
        ::Range
      end
    end
  end
end
