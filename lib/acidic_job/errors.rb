# frozen_string_literal: true

module AcidicJob
  class Error < StandardError
  end
  class RedefiningWorkflowError < Error
    def message = "can only call `execute_workflow` once within a job"
  end
  class UndefinedWorkflowBlockError < Error
    def message = "block must be passed to `execute_workflow`"
  end
  class InvalidWorkflowBlockError < Error
    def message = "workflow builder must be yielded to the `execute_workflow` block"
  end
  class MissingStepsError < Error
    def message = "workflow must define at least one step"
  end
  class ArgumentMismatchError < Error
    def initialize(expected, existing)
      @expected = expected
      @existing = existing
    end

    def message
      <<~TXT
        existing execution's arguments do not match
          existing: #{@existing.inspect}
          expected: #{@expected.inspect}
      TXT
    end
  end
  class DefinitionMismatchError < Error
    def initialize(expected, existing)
      @expected = expected
      @existing = existing
    end

    def message
      <<~TXT
        existing execution's definition does not match
          existing: #{@existing.inspect}
          expected: #{@expected.inspect}
      TXT
    end
  end
  class UndefinedStepError < Error
    def initialize(step)
      @step = step
    end

    def message = "workflow does not reference this step: #{@step.inspect}"
  end
  class SucceededStepError < Error
    def initialize(step)
      @step = step
    end

    def message = "workflow has already recorded this step as succeeded: #{@step.inspect}"
  end
  class UndefinedMethodError < Error
    def initialize(step)
      @step = step
    end

    def message = "Undefined step method: #{@step.inspect}"
  end
  class InvalidMethodError < Error
    def initialize(step)
      @step = step
    end

    def message = "step method cannot expect arguments: #{@step.inspect}"
  end
end
