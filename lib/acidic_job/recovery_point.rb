# frozen_string_literal: true

# Represents an action to set a new recovery point. One possible option for a
# return from an #atomic_phase block.
module AcidicJob
  class RecoveryPoint
    def initialize(name)
      @name = name
    end

    def call(run:)
      # Skip AR callbacks as there are none on the model
      run.update_column(:recovery_point, @name)
    end
  end
end
