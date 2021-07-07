# frozen_string_literal: true

require_relative "acidic_job/version"
require_relative "acidic_job/no_op"
require_relative "acidic_job/recovery_point"
require_relative "acidic_job/response"
require "active_support/concern"

# rubocop:disable Metrics/ModuleLength, Style/Documentation, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
module AcidicJob
  class IdempotencyKeyRequired < StandardError; end

  class MissingRequiredAttribute < StandardError; end

  class IdempotencyKeyTooShort < StandardError; end

  class MismatchedIdempotencyKeyAndJobArguments < StandardError; end

  class LockedIdempotencyKey < StandardError; end

  class UnknownRecoveryPoint < StandardError; end

  class UnknownAtomicPhaseType < StandardError; end

  class SerializedTransactionConflict < StandardError; end

  extend ActiveSupport::Concern

  included do
    attr_reader :key

    # discard_on MismatchedIdempotencyKeyAndJobArguments
    # discard_on UnknownRecoveryPoint
    # discard_on UnknownAtomicPhaseType
    # discard_on MissingRequiredAttribute
    # retry_on LockedIdempotencyKey
    # retry_on ActiveRecord::SerializationFailure
  end

  class_methods do
    def required(*names)
      required_attributes.push(*names)
    end

    def required_attributes
      return @required_attributes if instance_variable_defined?(:@required_attributes)

      @required_attributes = []
    end
  end

  # Number of seconds passed which we consider a held idempotency key lock to be
  # defunct and eligible to be locked again by a different API call. We try to
  # unlock keys on our various failure conditions, but software is buggy, and
  # this might not happen 100% of the time, so this is a hedge against it.
  IDEMPOTENCY_KEY_LOCK_TIMEOUT = 90

  # To try and enforce some level of required randomness in an idempotency key,
  # we require a minimum length. This of course is a poor approximate, and in
  # real life you might want to consider trying to measure actual entropy with
  # something like the Shannon entropy equation.
  IDEMPOTENCY_KEY_MIN_LENGTH = 20

  # &block
  def idempotently(key:, with:)
    # set accessors for each argument passed in to ensure they are available
    # to the step methods the job will have written
    define_accessors_for_passed_arguments(with)

    validate_passed_idempotency_key(key)
    validate_passed_arguments(with)

    # execute the block to gather the info on what phases are defined for this job
    defined_steps = yield

    # convert the array of steps into a hash of recovery_points and callable actions
    phases = define_atomic_phases(defined_steps)

    # find or create an AcidicJobKey record to store all information about this job
    # side-effect: will set the @key instance variable
    ensure_idempotency_key_record(key, with[:params], defined_steps.first)

    # if the key record is already marked as finished, immediately return its result
    return @key.succeeded? if @key.finished?

    # otherwise, we will enter a loop to process each required step of the job
    100.times do
      # our `phases` hash uses Symbols for keys
      recovery_point = @key.recovery_point.to_sym

      case recovery_point
      when :FINISHED
        break
      else
        raise UnknownRecoveryPoint unless phases.key? recovery_point

        atomic_phase @key, phases[recovery_point]
      end
    end

    # the loop will break once the job is finished, so simply report the status
    @key.succeeded?
  end

  def step(method_name)
    @_steps ||= []
    @_steps << method_name
    @_steps
  end

  private

  def atomic_phase(key = nil, proc = nil, &block)
    error = false
    phase_callable = (proc || block)

    begin
      # ActiveRecord::Base.transaction(isolation: :serializable) do
      ActiveRecord::Base.transaction(isolation: :read_uncommitted) do
        phase_result = phase_callable.call

        raise UnknownAtomicPhaseType unless phase_result.is_a?(NoOp) ||
                                            phase_result.is_a?(RecoveryPoint) ||
                                            phase_result.is_a?(Response)

        # TODO: why is this here?
        key ||= @key
        phase_result.call(key: key)
      end
    rescue StandardError => e
      error = e
      raise e
    ensure
      # If we're leaving under an error condition, try to unlock the idempotency
      # key right away so that another request can try again.
      if error && !key.nil?
        begin
          key.update_columns(locked_at: nil, error_object: error)
        rescue StandardError => e
          # We're already inside an error condition, so swallow any additional
          # errors from here and just send them to logs.
          puts "Failed to unlock key #{key.id} because of #{e}."
        end
      end
    end
  end

  def ensure_idempotency_key_record(key_val, params, first_step)
    atomic_phase do
      @key = AcidicJobKey.find_by(idempotency_key: key_val)

      if @key
        # Programs enqueuing multiple jobs with different parameters but the
        # same idempotency key is a bug.
        raise MismatchedIdempotencyKeyAndJobArguments if @key.job_args != params.as_json

        # Only acquire a lock if the key is unlocked or its lock has expired
        # because the original job was long enough ago.
        raise LockedIdempotencyKey if @key.locked_at && @key.locked_at > Time.current - IDEMPOTENCY_KEY_LOCK_TIMEOUT

        # Lock the key and update latest run unless the job is already
        # finished.
        @key.update!(last_run_at: Time.current, locked_at: Time.current) unless @key.finished?
      else
        @key = AcidicJobKey.create!(
          idempotency_key: key_val,
          locked_at: Time.current,
          last_run_at: Time.current,
          recovery_point: first_step,
          job_name: self.class.name,
          job_args: params.as_json
        )
      end

      # no response and no need to set a recovery point
      NoOp.new
    end
  end

  def define_accessors_for_passed_arguments(passed_arguments)
    passed_arguments.each do |accessor, value|
      # the reader method may already be defined
      self.class.attr_reader accessor unless respond_to?(accessor)
      # but we should always update the value to match the current value
      instance_variable_set("@#{accessor}", value)
    end

    true
  end

  def validate_passed_idempotency_key(key)
    raise IdempotencyKeyRequired if key.nil?
    raise IdempotencyKeyTooShort if key.length < IDEMPOTENCY_KEY_MIN_LENGTH

    true
  end

  def validate_passed_arguments(attributes)
    missing_attributes = self.class.required_attributes.select do |required_attribute|
      attributes[required_attribute].nil?
    end

    return if missing_attributes.empty?

    raise MissingRequiredAttribute,
          "The following required job parameters are missing: #{missing_attributes.to_sentence}"
  end

  def define_atomic_phases(defined_steps)
    defined_steps << :FINISHED

    {}.tap do |phases|
      defined_steps.each_cons(2).map do |enter_method, exit_method|
        phases[enter_method] = lambda do
          method(enter_method).call

          if exit_method == :FINISHED
            Response.new
          else
            RecoveryPoint.new(exit_method)
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength, Style/Documentation, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
