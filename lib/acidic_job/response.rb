# frozen_string_literal: true

# Represents an action to set a new API response (which will be stored onto an
# idempotency key). One  possible option for a return from an #atomic_phase
# block.
class Response
  def call(key:)
    key.update!(
      locked_at: nil,
      recovery_point: AcidicJobKey::RECOVERY_POINT_FINISHED
    )
  end
end
