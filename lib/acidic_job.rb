# frozen_string_literal: true

require_relative "acidic_job/version"
require_relative "acidic_job/errors"
require_relative "acidic_job/no_op"
require_relative "acidic_job/recovery_point"
require_relative "acidic_job/response"
require_relative "acidic_job/key"
require_relative "acidic_job/staged"
require_relative "acidic_job/perform_wrapper"
require_relative "acidic_job/perform_transactionally_extension"
require_relative "acidic_job/deliver_transactionally_extension"
require_relative "acidic_job/sidekiq_callbacks"
require "active_support/concern"

# rubocop:disable Metrics/ModuleLength, Metrics/AbcSize, Metrics/MethodLength
module AcidicJob
  extend ActiveSupport::Concern

  def self.wire_everything_up(klass)
    klass.attr_reader :key
    klass.attr_reader :staged_job_gid
    klass.attr_reader :arguments_for_perform

    # Extend ActiveJob with `perform_transactionally` class method
    klass.include PerformTransactionallyExtension

    ActionMailer::Parameterized::MessageDelivery.include DeliverTransactionallyExtension if defined?(ActionMailer)

    # Ensure our `perform` method always runs first to gather parameters
    klass.prepend PerformWrapper

    klass.prepend SidekiqCallbacks unless klass.respond_to?(:after_perform)

    klass.after_perform :delete_staged_job_record, if: :staged_job_gid
  end

  included do
    AcidicJob.wire_everything_up(self)
  end

  class_methods do
    def inherited(subclass)
      AcidicJob.wire_everything_up(subclass)
      super
    end

    def initiate(*args)
      operation = Sidekiq::Batch.new
      operation.on(:success, self, *args)
      operation.jobs do
        perform_async
      end
    end
  end

  # Number of seconds passed which we consider a held idempotency key lock to be
  # defunct and eligible to be locked again by a different job run. We try to
  # unlock keys on our various failure conditions, but software is buggy, and
  # this might not happen 100% of the time, so this is a hedge against it.
  IDEMPOTENCY_KEY_LOCK_TIMEOUT = 90

  # takes a block
  def with_acidity(given:)
    # execute the block to gather the info on what steps are defined for this job workflow
    steps = yield || []

    raise NoDefinedSteps if steps.empty?

    # convert the array of steps into a hash of recovery_points and next steps
    workflow = define_workflow(steps)

    # find or create a Key record (our idempotency key) to store all information about this job
    #
    # A key concept here is that if two requests try to insert or update within
    # close proximity, one of the two will be aborted by Postgres because we're
    # using a transaction with SERIALIZABLE isolation level. It may not look
    # it, but this code is safe from races.
    key = ensure_idempotency_key_record(idempotency_key_value, workflow, given)

    # begin the workflow
    process_key(key)
  end

  def process_key(key)
    @key = key

    # if the key record is already marked as finished, immediately return its result
    return @key.succeeded? if @key.finished?

    # otherwise, we will enter a loop to process each step of the workflow
    @key.workflow.size.times do
      recovery_point = @key.recovery_point.to_s
      current_step = @key.workflow[recovery_point]

      if recovery_point == Key::RECOVERY_POINT_FINISHED.to_s # rubocop:disable Style/GuardClause
        break
      elsif current_step.nil?
        raise UnknownRecoveryPoint, "Defined workflow does not reference this step: #{recovery_point}"
      elsif (jobs = current_step.fetch("awaits", [])).any?
        acidic_step @key, current_step
        # THIS MUST BE DONE AFTER THE KEY RECOVERY POINT HAS BEEN UPDATED
        enqueue_step_parallel_jobs(jobs)
        # after processing the current step, break the processing loop
        # and stop this method from blocking in the primary worker
        # as it will continue once the background workers all succeed
        # so we want to keep the primary worker queue free to process new work
        # this CANNOT ever be `break` as that wouldn't exit the parent job,
        # only this step in the workflow, blocking as it awaits the next step
        return true
      else
        acidic_step @key, current_step
      end
    end

    # the loop will break once the job is finished, so simply report the status
    @key.succeeded?
  end

  def step(method_name, awaits: [])
    @_steps ||= []

    @_steps << {
      "does" => method_name.to_s,
      "awaits" => awaits
    }

    @_steps
  end

  def safely_finish_acidic_job
    # Short circuits execution by sending execution right to 'finished'.
    # So, ends the job "successfully"
    AcidicJob::Response.new
  end

  private

  def delete_staged_job_record
    return unless staged_job_gid

    staged_job = GlobalID::Locator.locate(staged_job_gid)
    staged_job.delete
    true
  rescue ActiveRecord::RecordNotFound
    true
  end

  def define_workflow(steps)
    steps << { "does" => Key::RECOVERY_POINT_FINISHED }

    {}.tap do |workflow|
      steps.each_cons(2).map do |enter_step, exit_step|
        enter_name = enter_step["does"]
        workflow[enter_name] = {
          "then" => exit_step["does"]
        }.merge(enter_step)
      end
    end
  end

  def ensure_idempotency_key_record(key_val, workflow, accessors)
    isolation_level = case ActiveRecord::Base.connection.adapter_name.downcase.to_sym
                      when :sqlite
                        :read_uncommitted
                      else
                        :serializable
                      end

    ActiveRecord::Base.transaction(isolation: isolation_level) do
      key = Key.find_by(idempotency_key: key_val)

      if key.present?
        # Programs enqueuing multiple jobs with different parameters but the
        # same idempotency key is a bug.
        raise MismatchedIdempotencyKeyAndJobArguments if key.job_args != @arguments_for_perform

        # Only acquire a lock if the key is unlocked or its lock has expired
        # because the original job was long enough ago.
        raise LockedIdempotencyKey if key.locked_at && key.locked_at > Time.current - IDEMPOTENCY_KEY_LOCK_TIMEOUT

        # Lock the key and update latest run unless the job is already finished.
        key.update!(last_run_at: Time.current, locked_at: Time.current) unless key.finished?
      else
        key = Key.create!(
          idempotency_key: key_val,
          locked_at: Time.current,
          last_run_at: Time.current,
          recovery_point: workflow.first.first,
          job_name: self.class.name,
          job_args: @arguments_for_perform,
          workflow: workflow
        )
      end

      # set accessors for each argument passed in to ensure they are available
      # to the step methods the job will have written
      define_accessors_for_passed_arguments(accessors, key)

      # NOTE: we must return the `key` object from this transaction block
      # so that it can be returned from this method to the caller
      key
    end
  end

  def acidic_step(key, step)
    rescued_error = false
    step_callable = wrap_step_as_acidic_callable step

    begin
      key.with_lock do
        step_result = step_callable.call(key)

        step_result.call(key: key)
      end
    # QUESTION: Can an error not inherit from StandardError
    rescue StandardError => e
      rescued_error = e
      raise e
    ensure
      if rescued_error
        # If we're leaving under an error condition, try to unlock the idempotency
        # key right away so that another request can try again.3
        begin
          key.update_columns(locked_at: nil, error_object: rescued_error)
        rescue StandardError => e
          # We're already inside an error condition, so swallow any additional
          # errors from here and just send them to logs.
          puts "Failed to unlock key #{key.id} because of #{e}."
        end
      end
    end
  end

  def define_accessors_for_passed_arguments(passed_arguments, key)
    # first, get the current state of all accessors for both previously persisted and initialized values
    current_accessors = passed_arguments.stringify_keys.merge(key.attr_accessors)

    # next, ensure that `Key#attr_accessors` is populated with initial values
    key.update_column(:attr_accessors, current_accessors)

    current_accessors.each do |accessor, value|
      # the reader method may already be defined
      self.class.attr_reader accessor unless respond_to?(accessor)
      # but we should always update the value to match the current value
      instance_variable_set("@#{accessor}", value)
      # and we overwrite the setter to ensure any updates to an accessor update the `Key` stored value
      # Note: we must define the singleton method on the instance to avoid overwriting setters on other
      # instances of the same class
      define_singleton_method("#{accessor}=") do |current_value|
        instance_variable_set("@#{accessor}", current_value)
        key.attr_accessors[accessor] = current_value
        key.save!(validate: false)
        current_value
      end
    end

    true
  end

  # rubocop:disable Metrics/PerceivedComplexity
  def wrap_step_as_acidic_callable(step)
    # {:then=>:next_step, :does=>:enqueue_step, :awaits=>[WorkerWithEnqueueStep::FirstWorker]}
    current_step = step["does"]
    next_step = step["then"]

    callable = if respond_to? current_step, _include_private = true
                 method(current_step)
               else
                 proc {} # no-op
               end

    proc do |key|
      result = if callable.arity.zero?
                 callable.call
               elsif callable.arity == 1
                 callable.call(key)
               else
                 raise TooManyParametersForStepMethod
               end

      if result.is_a?(Response)
        result
      elsif next_step.to_s == Key::RECOVERY_POINT_FINISHED
        Response.new
      else
        RecoveryPoint.new(next_step)
      end
    end
  end
  # rubocop:enable Metrics/PerceivedComplexity

  def enqueue_step_parallel_jobs(jobs)
    # TODO: GIVE PROPER ERROR
    # `batch` is available from Sidekiq::Pro
    raise SidekiqBatchRequired unless defined?(Sidekiq::Batch)

    batch.jobs do
      step_batch = Sidekiq::Batch.new
      # step_batch.description = "AcidicJob::Workflow Step: #{step}"
      step_batch.on(
        :success,
        "#{self.class.name}#step_done",
        # NOTE: options are marshalled through JSON so use only basic types.
        { "key_id" => @key.id }
      )
      # NOTE: The jobs method is atomic.
      # All jobs created in the block are actually pushed atomically at the end of the block.
      # If an error is raised, none of the jobs will go to Redis.
      step_batch.jobs do
        jobs.each do |worker_name|
          worker = worker_name.is_a?(String) ? worker_name.constantize : worker_name
          if worker.instance_method(:perform).arity.zero?
            worker.perform_async
          elsif worker.instance_method(:perform).arity == 1
            worker.perform_async(key.id)
          else
            raise TooManyParametersForParallelJob
          end
        end
      end
    end
  end

  def idempotency_key_value
    return job_id if defined?(job_id) && !job_id.nil?
    return jid if defined?(jid) && !jid.nil?

    Digest::SHA1.hexdigest [self.class.name, arguments_for_perform].flatten.join
  end

  def step_done(_status, options)
    key = Key.find(options["key_id"])
    # when a batch of jobs for a step succeeds, we begin the key processing again
    process_key(key)
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/AbcSize, Metrics/MethodLength
