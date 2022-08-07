# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module Mixin
    extend ActiveSupport::Concern

    def self.wire_up(other)
      raise UnknownJobAdapter unless (defined?(::ActiveJob::Base) && other < ::ActiveJob::Base) ||
                                     (defined?(::Sidekiq::Worker) && other.include?(::Sidekiq::Worker))

      # Ensure our `perform` method always runs first to gather parameters
      # and run perform callbacks for Sidekiq workers
      other.prepend PerformWrapper

      # By default, we unique job runs by the `job_id`
      other.instance_variable_set(:@acidic_identifier, :job_id)
      # However, you can customize this behavior on a per job class level
      other.define_singleton_method(:acidic_by_job_identifier) { @acidic_identifier = :job_id }
      # You could unique job runs by the arguments passed to the job (e.g. memoization)
      other.define_singleton_method(:acidic_by_job_arguments) { @acidic_identifier = :job_arguments }
      # Or, you could unique jobs run by any logic you'd like using a block
      other.define_singleton_method(:acidic_by) { |&block| @acidic_identifier = block }

      # We add a callback to ensure that staged, non-workflow jobs are "finished" after they are "performed".
      # This allows us to ensure that we can always inspect whether a run is finished and get correct data
      other.set_callback :perform, :after, :finish_staged_job, if: -> { was_staged_job? && !was_workflow_job? }
      # We also allow you to write any of your own callbacks keyed to the "finish" event.
      # The "finish" event is notably different from the "perform" event for acidic jobs,
      # as any acidic job can have one or more "perform" event (retries or a resume after awaiting jobs),
      # but will only ever have one "finish" event (when the run successfully completes)
      other.define_callbacks :finish
    end

    included do
      Mixin.wire_up(self)
    end

    class_methods do
      def inherited(subclass)
        Mixin.wire_up(subclass)
        super
      end

      # `perform_now` runs a job synchronously and immediately
      # `perform_later` runs a job asynchronously and queues it immediately
      # `perform_acidicly` run a job asynchronously and queues it after a successful database commit
      def perform_acidicly(*args, **kwargs)
        job = new(*args, **kwargs)

        Run.stage!(job)
      end

      # Instantiate an instance of a job ready for serialization
      def with(...)
        # New delegation syntax (...) was introduced in Ruby 2.7.
        # https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/
        job = new(...)
        # force the job to resolve the `queue_name`, so that we don't try to serialize a Proc into ActiveRecord
        job.queue_name
        job
      end
    end

    def idempotency_key
      IdempotencyKey.new(self).value(acidic_by: acidic_identifier)
    end

    protected

    # Short circuits execution by sending execution right to 'finished'.
    # So, ends the job "successfully"
    def safely_finish_acidic_job
      FinishedPoint.new
    end

    def with_acidic_workflow(persisting: {}, &block)
      raise RedefiningWorkflow if defined? @workflow_builder

      @workflow_builder = WorkflowBuilder.new

      raise MissingWorkflowBlock, "A block must be passed to `with_acidic_workflow`" unless block_given?

      if block.arity.zero?
        @workflow_builder.instance_exec(&block)
      else
        yield @workflow_builder
      end

      raise NoDefinedSteps if @workflow_builder.steps.empty?

      # convert the array of steps into a hash of recovery_points and next steps
      workflow = @workflow_builder.define_workflow

      ensure_run_record_and_process(workflow, persisting)
    rescue LocalJumpError
      raise MissingWorkflowBlock, "A block must be passed to `with_acidic_workflow`"
    end

    # DEPRECATED
    # second attempt at the DSL, but `providing` suggested you needed to serialize
    # any data that would be used in step methods, but simply instance variables work.
    def with_acidity(providing: {}, &block)
      ::ActiveSupport::Deprecation.new("1.0", "AcidicJob").deprecation_warning(:with_acidity)

      @workflow_builder = WorkflowBuilder.new
      @workflow_builder.instance_exec(&block)

      raise NoDefinedSteps if @workflow_builder.steps.empty?

      # convert the array of steps into a hash of recovery_points and next steps
      workflow = @workflow_builder.define_workflow

      ensure_run_record_and_process(workflow, providing)
    rescue LocalJumpError
      raise MissingWorkflowBlock, "A block must be passed to `with_acidity`"
    end

    # DEPRECATED
    # first attempt at the DSL, but `idempotently` and `with` are too distant from the gem name.
    def idempotently(with: {}, &block)
      ::ActiveSupport::Deprecation.new("1.0", "AcidicJob").deprecation_warning(:idempotently)

      @workflow_builder = WorkflowBuilder.new
      @workflow_builder.instance_exec(&block)

      raise NoDefinedSteps if @workflow_builder.steps.empty?

      # convert the array of steps into a hash of recovery_points and next steps
      workflow = @workflow_builder.define_workflow

      ensure_run_record_and_process(workflow, with)
    rescue LocalJumpError
      raise MissingWorkflowBlock, "A block must be passed to `idempotently`"
    end

    private

    # You can always retrieve the unique identifier from within the job instance itself
    def acidic_identifier
      self.class.instance_variable_get(:@acidic_identifier)
    end

    def ensure_run_record_and_process(workflow, persisting)
      ::AcidicJob.logger.log_run_event("Initializing run...", self, nil)
      @acidic_job_run = ::ActiveRecord::Base.transaction(isolation: acidic_isolation_level) do
        run = Run.find_by(idempotency_key: idempotency_key)
        serialized_job = serialize

        if run.present?
          # Programs enqueuing multiple jobs with different parameters but the
          # same idempotency key is a bug.
          if run.serialized_job["arguments"] != serialized_job["arguments"]
            raise MismatchedIdempotencyKeyAndJobArguments
          end

          # Only acquire a lock if the key is unlocked or its lock has expired
          # because the original job was long enough ago.
          raise LockedIdempotencyKey if run.lock_active?

          run.update!(
            last_run_at: Time.current,
            locked_at: Time.current,
            # staged workflow jobs won't have the `workflow` or `recovery_point` stored when staged,
            # so we need to persist both here.
            workflow: workflow,
            recovery_point: run.recovery_point || workflow.keys.first
          )
        else
          run = Run.create!(
            staged: false,
            idempotency_key: idempotency_key,
            job_class: self.class.name,
            locked_at: Time.current,
            last_run_at: Time.current,
            workflow: workflow,
            recovery_point: workflow.keys.first,
            serialized_job: serialize
          )
        end

        # persist `persisting` values and set accessors for each
        # first, get the current state of all accessors for both previously persisted and initialized values
        current_accessors = persisting.stringify_keys.merge(run.attr_accessors)

        # next, ensure that `Run#attr_accessors` is populated with initial values
        # skip validations for this call to ensure a write
        run.update_column(:attr_accessors, current_accessors) if current_accessors != run.attr_accessors

        # finally, set reader and writer methods
        current_accessors.each do |accessor, value|
          # the reader method may already be defined
          self.class.attr_reader accessor unless respond_to?(accessor)
          # but we should always update the value to match the current value
          instance_variable_set("@#{accessor}", value)
          # and we overwrite the setter to ensure any updates to an accessor update the `Run` stored value
          # Note: we must define the singleton method on the instance to avoid overwriting setters on other
          # instances of the same class
          define_singleton_method("#{accessor}=") do |updated_value|
            instance_variable_set("@#{accessor}", updated_value)
            run.attr_accessors[accessor] = updated_value
            run.save!(validate: false)
            updated_value
          end
        end

        # ensure that we return the `run` record so that the result of this block is the record
        run
      end
      ::AcidicJob.logger.log_run_event("Initialized run.", self, @acidic_job_run)

      Processor.new(@acidic_job_run, self).process_run
    end

    def was_staged_job?
      job_id.start_with? Run::STAGED_JOB_ID_PREFIX
    end

    def was_workflow_job?
      return false unless defined? @acidic_job_run

      @acidic_job_run.present?
    end

    def staged_job_run
      return unless was_staged_job?
      # memoize so we don't have to make unnecessary database calls
      return @staged_job_run if defined? @staged_job_run

      # "STG__#{idempotency_key}__#{encoded_global_id}"
      _prefix, _idempotency_key, encoded_global_id = job_id.split("__")
      staged_job_gid = "gid://#{::Base64.decode64(encoded_global_id)}"

      @staged_job_run = ::GlobalID::Locator.locate(staged_job_gid)
    end

    def finish_staged_job
      staged_job_run.finish!
    end

    def acidic_isolation_level
      case ::ActiveRecord::Base.connection.adapter_name.downcase.to_sym
      # SQLite doesn't support `serializable` transactions,
      # so we use the strictest isolation_level is does support
      when :sqlite
        :read_uncommitted
      else
        :serializable
      end
    end
  end
end
