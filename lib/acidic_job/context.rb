# frozen_string_literal: true

module AcidicJob
  class Context
    def initialize(execution)
      @execution = execution
    end

    def set(hash)
      AcidicJob.instrument(:set_context, **hash) do
        AcidicJob::Value.upsert_all(
          hash.map do |key, value|
            {
              execution_id: @execution.id,
              key: key,
              value: value,
            }
          end,
          unique_by: %i[execution_id key]
        )
      end
    end

    def get(*keys)
      AcidicJob.instrument(:get_context, keys: keys) do
        @execution.values.select(:value).where(key: keys).pluck(:value)
      end
    end

    # TODO: deprecate these methods
    def []=(key, value)
      set(key => value)
    end

    def [](key)
      get(key).first
    end
  end
end
