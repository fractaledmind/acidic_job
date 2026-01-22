# frozen_string_literal: true

require "active_job/serializers/object_serializer"

module AcidicJob
  module Serializers
    # This serializer is only used for Rails versions prior to 7.1,
    # which introduced ActiveJob::Serializers::RangeSerializer.
    class RangeSerializer < ::ActiveJob::Serializers::ObjectSerializer
      KEYS = %w[begin end exclude_end].freeze

      def serialize(range)
        args = ::ActiveJob::Arguments.serialize([range.begin, range.end, range.exclude_end?])
        super(KEYS.zip(args).to_h)
      end

      def deserialize(hash)
        klass.new(*::ActiveJob::Arguments.deserialize(hash.values_at(*KEYS)))
      end

      def klass
        ::Range
      end
    end
  end
end
