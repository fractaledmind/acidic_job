# frozen_string_literal: true

require_relative "acidic_job/version"
require_relative "acidic_job/errors"
require_relative "acidic_job/recovery_point"
require_relative "acidic_job/finished_point"
require_relative "acidic_job/run"
require_relative "acidic_job/step"
require_relative "acidic_job/staging"
require_relative "acidic_job/awaiting"
require_relative "acidic_job/perform_wrapper"
require_relative "acidic_job/idempotency_key"
require_relative "acidic_job/extensions/sidekiq"
require_relative "acidic_job/extensions/action_mailer"
require_relative "acidic_job/extensions/active_job"
require_relative "acidic_job/extensions/noticed"
require_relative "acidic_job/upgrade_service"

require "active_support/concern"
require "active_job/queue_adapters"
require "active_job/base"

module AcidicJob
  extend ActiveSupport::Concern

  IDEMPOTENCY_KEY_LOCK_TIMEOUT = 90

  def self.wire_everything_up(klass)
    # Ensure our `perform` method always runs first to gather parameters
    klass.prepend PerformWrapper

    klass.include Staging
    klass.include Awaiting

    # Add `deliver_acidicly` to ActionMailer
    ActionMailer::Parameterized::MessageDelivery.include Extensions::ActionMailer if defined?(ActionMailer)
    # Add `deliver_acidicly` to Noticed
    Noticed::Base.include Extensions::Noticed if defined?(Noticed)

    if defined?(ActiveJob) && klass < ActiveJob::Base
      klass.send(:include, Extensions::ActiveJob)
    elsif defined?(Sidekiq) && klass.include?(Sidekiq::Worker)
      klass.send(:include, Extensions::Sidekiq)
      klass.include ActiveSupport::Callbacks
      klass.define_callbacks :perform
    else
      raise UnknownJobAdapter
    end

    # TODO: write test for a staged job that uses awaits
    klass.set_callback :perform, :after, :reenqueue_awaited_by_job,
                       if: -> { was_awaited_job? && !was_workflow_job? }
    klass.set_callback :perform, :after, :finish_staged_job, if: -> { was_staged_job? && !was_workflow_job? }
    klass.define_callbacks :finish
    klass.set_callback :finish, :after, :reenqueue_awaited_by_job,
                       if: -> { was_workflow_job? && was_awaited_job? }

    klass.instance_variable_set(:@acidic_identifier, :job_id)
    klass.define_singleton_method(:acidic_by_job_id) { @acidic_identifier = :job_id }
    klass.define_singleton_method(:acidic_by_job_args) { @acidic_identifier = :job_args }
    klass.define_singleton_method(:acidic_by) { |proc| @acidic_identifier = proc }
    klass.attr_reader(:acidic_job_run)
  end

  included do
    AcidicJob.wire_everything_up(self)
  end

  class_methods do
    def inherited(subclass)
      AcidicJob.wire_everything_up(subclass)
      super
    end

    def with(*args, **kwargs)
      new(*args, **kwargs)
    end

    def acidic_identifier
      @acidic_identifier
    end
  end

  def initialize(*args, **kwargs)
    # ensure this instance variable is always defined
    @__acidic_job_steps = []
    @__acidic_job_args = args
    @__acidic_job_kwargs = kwargs

    super(*args, **kwargs)
  rescue ArgumentError => e
    raise e unless e.message.include?("wrong number of arguments")

    super()
  end

  def with_acidity(providing: {})
    # execute the block to gather the info on what steps are defined for this job workflow
    yield

    # check that the block actually defined at least one step
    # TODO: WRITE TESTS FOR FAULTY BLOCK VALUES
    raise NoDefinedSteps if @__acidic_job_steps.nil? || @__acidic_job_steps.empty?

    # convert the array of steps into a hash of recovery_points and next steps
    workflow = define_workflow(@__acidic_job_steps)

    @acidic_job_run = ensure_run_record(workflow, providing)

    # begin the workflow
    process_run(@acidic_job_run)
  end

  # DEPRECATED
  def idempotently(with: {}, &blk)
    ActiveSupport::Deprecation.new("1.0", "AcidicJob").deprecation_warning(:idempotently)
    with_acidity(providing: with, &blk)
  end

  def safely_finish_acidic_job
    # Short circuits execution by sending execution right to 'finished'.
    # So, ends the job "successfully"
    FinishedPoint.new
  end

  # rubocop:disable Naming/MemoizedInstanceVariableName
  def idempotency_key
    if defined?(@__acidic_job_idempotency_key) && !@__acidic_job_idempotency_key.nil?
      return @__acidic_job_idempotency_key
    end

    acidic_identifier = self.class.acidic_identifier
    @__acidic_job_idempotency_key ||= IdempotencyKey.new(acidic_identifier)
                                                    .value_for(self, *@__acidic_job_args, **@__acidic_job_kwargs)
  end
  # rubocop:enable Naming/MemoizedInstanceVariableName

  private

  def finish_staged_job
    FinishedPoint.new.call(run: staged_job_run)
  end

  def was_workflow_job?
    defined?(@acidic_job_run) && @acidic_job_run.present?
  end

  def process_run(run)
    # if the run record is already marked as finished, immediately return its result
    return run.succeeded? if run.finished?

    # otherwise, we will enter a loop to process each step of the workflow
    loop do
      recovery_point = run.recovery_point.to_s
      current_step = run.workflow[recovery_point]

      # if any step calls `safely_finish_acidic_job` or the workflow has simply completed,
      # be sure to break out of the loop
      if recovery_point.to_s == Run::FINISHED_RECOVERY_POINT.to_s # rubocop:disable Style/GuardClause
        break
      elsif current_step.nil?
        raise UnknownRecoveryPoint, "Defined workflow does not reference this step: #{recovery_point}"
      elsif !Array(jobs = current_step.fetch("awaits", []) || []).compact.empty?
        step = Step.new(current_step, run, self)
        # Only execute the current step, without yet progressing the recovery_point to the next step.
        # This ensures that any failures in parallel jobs will have this step retried in the main workflow
        step_result = step.execute
        # We allow the `#step_done` method to manage progressing the recovery_point to the next step,
        # and then calling `process_run` to restart the main workflow on the next step.
        # We pass the `step_result` so that the async callback called after the step-parallel-jobs complete
        # can move on to the appropriate next stage in the workflow.
        enqueue_step_parallel_jobs(jobs, run, step_result)
        # after processing the current step, break the processing loop
        # and stop this method from blocking in the primary worker
        # as it will continue once the background workers all succeed
        # so we want to keep the primary worker queue free to process new work
        # this CANNOT ever be `break` as that wouldn't exit the parent job,
        # only this step in the workflow, blocking as it awaits the next step
        return true
      else
        step = Step.new(current_step, run, self)
        step.execute
        # As this step does not await any parallel jobs, we can immediately progress to the next step
        step.progress
      end
    end

    # the loop will break once the job is finished, so simply report the status
    run.succeeded?
  end

  def step(method_name, awaits: [], for_each: nil)
    @__acidic_job_steps ||= []

    @__acidic_job_steps << {
      "does" => method_name.to_s,
      "awaits" => awaits,
      "for_each" => for_each
    }

    @__acidic_job_steps
  end

  def define_workflow(steps)
    # [ { does: "step 1", awaits: [] }, { does: "step 2", awaits: [] }, ... ]
    steps << { "does" => Run::FINISHED_RECOVERY_POINT }

    {}.tap do |workflow|
      steps.each_cons(2).map do |enter_step, exit_step|
        enter_name = enter_step["does"]
        workflow[enter_name] = enter_step.merge("then" => exit_step["does"])
      end
    end
    # { "step 1": { does: "step 1", awaits: [], then: "step 2" }, ...  }
  end

  def ensure_run_record(workflow, accessors)
    isolation_level = case ActiveRecord::Base.connection.adapter_name.downcase.to_sym
                      when :sqlite
                        :read_uncommitted
                      else
                        :serializable
                      end

    ActiveRecord::Base.transaction(isolation: isolation_level) do
      run = Run.find_by(idempotency_key: idempotency_key)
      serialized_job = serialize_job(*@__acidic_job_args, **@__acidic_job_kwargs)

      if run.present?
        # Programs enqueuing multiple jobs with different parameters but the
        # same idempotency key is a bug.
        if run.serialized_job.slice("args", "arguments") != serialized_job.slice("args", "arguments")
          raise MismatchedIdempotencyKeyAndJobArguments
        end

        # Only acquire a lock if the key is unlocked or its lock has expired
        # because the original job was long enough ago.
        raise LockedIdempotencyKey if run.locked_at && run.locked_at > Time.current - IDEMPOTENCY_KEY_LOCK_TIMEOUT

        # Lock the run and update latest run unless the job is already finished.
        unless run.finished?
          run.update!(
            last_run_at: Time.current,
            locked_at: Time.current,
            workflow: workflow,
            recovery_point: run.recovery_point || workflow.first.first
          )
        end
      else
        run = Run.create!(
          staged: false,
          idempotency_key: idempotency_key,
          job_class: self.class.name,
          locked_at: Time.current,
          last_run_at: Time.current,
          recovery_point: workflow.first.first,
          workflow: workflow,
          serialized_job: serialized_job
        )
      end

      # set accessors for each argument passed in to ensure they are available
      # to the step methods the job will have written
      define_accessors_for_passed_arguments(accessors, run)

      # NOTE: we must return the `key` object from this transaction block
      # so that it can be returned from this method to the caller
      run
    end
  end

  def define_accessors_for_passed_arguments(passed_arguments, run)
    # first, get the current state of all accessors for both previously persisted and initialized values
    current_accessors = passed_arguments.stringify_keys.merge(run.attr_accessors)

    # next, ensure that `Run#attr_accessors` is populated with initial values
    run.update_column(:attr_accessors, current_accessors)

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
        run.attr_accessors[accessor] = current_value
        run.save!(validate: false)
        current_value
      end
    end

    true
  end
end
