# frozen_string_literal: true

module AcidicJob
  class Error < StandardError; end

  class MismatchedIdempotencyKeyAndJobArguments < Error; end

  class LockedIdempotencyKey < Error; end

  class UnknownRecoveryPoint < Error; end

  class UnknownAtomicPhaseType < Error; end

  class SerializedTransactionConflict < Error; end

  class UnknownJobAdapter < Error; end

  class NoDefinedSteps < Error; end

  class SidekiqBatchRequired < Error; end

  class TooManyParametersForStepMethod < Error; end

  class TooManyParametersForParallelJob < Error; end

  class UnknownSerializedJobIdentifier < Error; end

  class IdempotencyKeyUndefined < Error; end
end
