# frozen_string_literal: true

# Represents an action to set a new API response (which will be stored onto an
# idempotency key). One  possible option for a return from an #atomic_phase
# block.
module AcidicJob
  class Response
    def call(key:)
      # Skip AR callbacks as there are none on the model
      key.update_columns(
        locked_at: nil,
        recovery_point: Key::RECOVERY_POINT_FINISHED
      )
    end
  end
end
