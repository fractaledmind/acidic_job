# frozen_string_literal: true

module AcidicJob
  class Context
    def initialize(execution)
      @execution = execution
    end

    def set(hash)
      AcidicJob.instrument(:set_context, **hash) do
        records = hash.map do |key, value|
          {
            execution_id: @execution.id,
            key: key,
            value: value,
          }
        end

        case AcidicJob::Value.connection.adapter_name.downcase.to_sym
        when :postgresql, :sqlite
          AcidicJob::Value.upsert_all(records, unique_by: [:execution_id, :key])
        when :mysql2, :mysql, :trilogy
          AcidicJob::Value.upsert_all(records)
        else
          # Fallback for other adapters - try with unique_by first, fall back without
          begin
            AcidicJob::Value.upsert_all(records, unique_by: [:execution_id, :key])
          rescue ArgumentError => e
            if e.message.include?('does not support :unique_by')
              AcidicJob::Value.upsert_all(records)
            else
              raise
            end
          end
        end
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
