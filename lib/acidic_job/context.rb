# frozen_string_literal: true

module AcidicJob
  class Context
    def initialize(execution)
      @execution = execution
    end

    def []=(key, value)
      AcidicJob.instrument(:set_context, key: key, value: value) do
        @execution.values.create!(
          key: key,
          value: value
        )
      end
    end

    def [](key)
      AcidicJob.instrument(:get_context, key: key, value: value) do
        @execution.values.select(:value).find_by(key: key).value
      end
    end
  end
end
