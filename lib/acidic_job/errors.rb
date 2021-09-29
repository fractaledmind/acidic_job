module AcidicJob
  class Error < StandardError; end

  class MismatchedIdempotencyKeyAndJobArguments < Error; end

  class LockedIdempotencyKey < Error; end

  class UnknownRecoveryPoint < Error; end

  class UnknownAtomicPhaseType < Error; end

  class SerializedTransactionConflict < Error; end

  class UnknownJobAdapter < Error; end
end