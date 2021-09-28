# frozen_string_literal: true

require_relative "acidic_job/version"
require_relative "acidic_job/no_op"
require_relative "acidic_job/recovery_point"
require_relative "acidic_job/response"
require_relative "acidic_job/key"
require_relative "acidic_job/staged"
require "active_support/concern"

# rubocop:disable Metrics/ModuleLength, Metrics/AbcSize, Metrics/MethodLength
module AcidicJob
  class MismatchedIdempotencyKeyAndJobArguments < StandardError; end

  class LockedIdempotencyKey < StandardError; end

  class UnknownRecoveryPoint < StandardError; end

  class UnknownAtomicPhaseType < StandardError; end

  class SerializedTransactionConflict < StandardError; end

  extend ActiveSupport::Concern

  module ActiveJobExtension
    extend ActiveSupport::Concern

    class_methods do
      def perform_transactionally(*args)
        attributes = if self < ActiveJob::Base
          {
            adapter: "activejob",
            job_name: self.name,
            job_args: job_or_instantiate(*args).serialize
          }
        else
          {
            adapter: "sidekiq",
            job_name: self.name,
            job_args: args
          }
        end
        AcidicJob::Staged.create!(attributes)
      end
    end
  end

  module ParameterWrapper
    def perform(*args, **kwargs)
      @arguments_for_perform = if args.any? && kwargs.any?
        args + [kwargs]
      elsif args.any? && kwargs.none?
        args
      elsif args.none? && kwargs.any?
        [kwargs]
      else
        []
      end
      super
    end
  end

  included do
    attr_reader :key
    attr_accessor :arguments_for_perform

    # Extend ActiveJob with `perform_transactionally` class method
    include ActiveJobExtension

    # Ensure our `perform` method always runs first to gather parameters
    prepend ParameterWrapper
  end

  # Number of seconds passed which we consider a held idempotency key lock to be
  # defunct and eligible to be locked again by a different job run. We try to
  # unlock keys on our various failure conditions, but software is buggy, and
  # this might not happen 100% of the time, so this is a hedge against it.
  IDEMPOTENCY_KEY_LOCK_TIMEOUT = 90

  # &block
  # &block
  def idempotently(with:)
    # set accessors for each argument passed in to ensure they are available
    # to the step methods the job will have written
    define_accessors_for_passed_arguments(with)

    # execute the block to gather the info on what phases are defined for this job
    defined_steps = yield
    # [:create_ride_and_audit_record, :create_stripe_charge, :send_receipt]

    # convert the array of steps into a hash of recovery_points and callable actions
    phases = define_atomic_phases(defined_steps)
    # { create_ride_and_audit_record: <#Method >, ... }

    # find or create an Key record (our idempotency key) to store all information about this job
    # side-effect: will set the @key instance variable
    #
    # A key concept here is that if two requests try to insert or update within
    # close proximity, one of the two will be aborted by Postgres because we're
    # using a transaction with SERIALIZABLE isolation level. It may not look
    # it, but this code is safe from races.
    ensure_idempotency_key_record(idempotency_key_value, defined_steps.first)

    # if the key record is already marked as finished, immediately return its result
    return @key.succeeded? if @key.finished?

    # otherwise, we will enter a loop to process each required step of the job
    100.times do
      # our `phases` hash uses Symbols for keys
      recovery_point = @key.recovery_point.to_sym

      case recovery_point
      when Key::RECOVERY_POINT_FINISHED.to_sym
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

  def atomic_phase(key, proc = nil, &block)
    error = false
    phase_callable = (proc || block)

    begin
      key.with_lock do
        phase_result = phase_callable.call

        phase_result.call(key: key)
      end
    rescue StandardError => e
      error = e
      raise e
    ensure
      # If we're leaving under an error condition, try to unlock the idempotency
      # key right away so that another request can try again.
      begin
        key.update_columns(locked_at: nil, error_object: error) if error.present?
      rescue StandardError => e
        # We're already inside an error condition, so swallow any additional
        # errors from here and just send them to logs.
        puts "Failed to unlock key #{key.id} because of #{e}."
      end
    end
  end

  def ensure_idempotency_key_record(key_val, first_step)
    isolation_level = case ActiveRecord::Base.connection.adapter_name.downcase.to_sym
                      when :sqlite
                        :read_uncommitted
                      else
                        :serializable
                      end

    ActiveRecord::Base.transaction(isolation: isolation_level) do
      @key = Key.find_by(idempotency_key: key_val)

      if @key
        # Programs enqueuing multiple jobs with different parameters but the
        # same idempotency key is a bug.
        if @key.job_args != @arguments_for_perform
          raise MismatchedIdempotencyKeyAndJobArguments
        end

        # Only acquire a lock if the key is unlocked or its lock has expired
        # because the original job was long enough ago.
        raise LockedIdempotencyKey if @key.locked_at && @key.locked_at > Time.current - IDEMPOTENCY_KEY_LOCK_TIMEOUT

        # Lock the key and update latest run unless the job is already finished.
        @key.update!(last_run_at: Time.current, locked_at: Time.current) unless @key.finished?
      else
        @key = Key.create!(
          idempotency_key: key_val,
          locked_at: Time.current,
          last_run_at: Time.current,
          recovery_point: first_step,
          job_name: self.class.name,
          job_args: @arguments_for_perform
        )
      end
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

  def define_atomic_phases(defined_steps)
    defined_steps << Key::RECOVERY_POINT_FINISHED

    {}.tap do |phases|
      defined_steps.each_cons(2).map do |enter_method, exit_method|
        phases[enter_method] = lambda do
          method(enter_method).call

          if exit_method.to_s == Key::RECOVERY_POINT_FINISHED
            Response.new
          else
            RecoveryPoint.new(exit_method)
          end
        end
      end
    end
  end

  def idempotency_key_value
    return job_id if defined?(job_id) && !job_id.nil?

    return jid if defined?(jid) && !jid.nil?

    require 'securerandom'

    SecureRandom.hex
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/AbcSize, Metrics/MethodLength
