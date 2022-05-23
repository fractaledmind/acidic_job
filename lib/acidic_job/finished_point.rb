# frozen_string_literal: true

require_relative "run"

# Represents an action to set a new API response (which will be stored onto an
# idempotency key). One  possible option for a return from an #atomic_phase
# block.
module AcidicJob
  class FinishedPoint
    def call(run:)
      # Skip AR callbacks as there are none on the model
      run.update_columns(
        locked_at: nil,
        recovery_point: Run::FINISHED_RECOVERY_POINT
      )
    end
  end
end
