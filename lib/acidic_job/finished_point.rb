# frozen_string_literal: true

require_relative "run"

# Represents an action to set a new API response (which will be stored onto an
# idempotency key). One  possible option for a return from an #atomic_phase
# block.
module AcidicJob
  class FinishedPoint
    def call(run:)
      run.finish!
    end
  end
end
