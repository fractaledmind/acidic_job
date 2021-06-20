# Represents an action to perform a no-op. One possible option for a return
# from an #atomic_phase block.
class NoOp
  def call(_key)
    # no-op
  end
end
