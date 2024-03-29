# frozen_string_literal: true

# Represents an action to set a new recovery point. One possible option for a
# return from an #atomic_phase block.
module AcidicJob
  class RecoveryPoint
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def call(run:)
      run.recover_to!(@name)
    end
  end
end
