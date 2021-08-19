# frozen_string_literal: true

# Represents an action to set a new recovery point. One possible option for a
# return from an #atomic_phase block.
module AcidicJob
  class RecoveryPoint
    attr_accessor :name

    def initialize(name)
      self.name = name
    end

    def call(key:)
      key.update_column(:recovery_point, name)
    end
  end
end
