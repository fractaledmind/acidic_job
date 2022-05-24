# frozen_string_literal: true

module AcidicJob
  class Error < StandardError; end
  class MissingWorkflowBlock < Error; end
  class UnknownRecoveryPoint < Error; end
  class NoDefinedSteps < Error; end
  class RedefiningWorkflow < Error; end
  class UndefinedStepMethod < Error; end
  class UnknownForEachCollection < Error; end
  class UniterableForEachCollection < Error; end
  class UnknownJobAdapter < Error; end
  class UnknownAwaitedJob < Error; end
end
