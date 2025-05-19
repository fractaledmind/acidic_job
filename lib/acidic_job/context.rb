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
      AcidicJob.instrument(:set_context, key: key, value: value) do
        AcidicJob::Value.upsert(
          {
            execution_id: @execution.id,
            key: key,
            value: value,
          },
          unique_by: %i[execution_id key]
        )
      end
    end

    def [](key)
      AcidicJob.instrument(:get_context, key: key) do
        @execution.values.select(:value).find_by(key: key)&.value
      end
    end
  end
end
