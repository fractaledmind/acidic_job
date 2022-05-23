# frozen_string_literal: true

module AcidicJob
  module Mixin
    extend ActiveSupport::Concern

    def self.included(other)
      raise UnknownJobAdapter unless defined?(ActiveJob) && other < ActiveJob::Base

      other.instance_variable_set(:@acidic_identifier, :job_id)
      other.define_singleton_method(:acidic_by_job_identifier) { @acidic_identifier = :job_identifier }
      other.define_singleton_method(:acidic_by_job_arguments) { @acidic_identifier = :job_arguments }
      other.define_singleton_method(:acidic_by) { |&block| @acidic_identifier = block }
      other.define_singleton_method(:acidic_identifier) { @acidic_identifier }

      # other.set_callback :perform, :after, :finish_staged_job, if: -> { was_staged_job? && !was_workflow_job? }
      other.set_callback :perform, :after, :reenqueue_awaited_by_job, if: -> { was_awaited_job? && !was_workflow_job? }
      other.define_callbacks :finish
      other.set_callback :finish, :after, :reenqueue_awaited_by_job, if: -> { was_awaited_job? && was_workflow_job? }
    end

    class_methods do
      def perform_acidicly(*args, **kwargs)
        job = new(*args, **kwargs)

        AcidicJob::Run.create!(
          staged: true,
          job_class: name,
          serialized_job: job.serialize,
          idempotency_key: job.idempotency_key
        )
      end

      def with(*args, **kwargs)
        # force the job to resolve the `queue_name`, so that we don't try to serialize a Proc into ActiveRecord
        job = new(*args, **kwargs)
        serialized = job.serialize
        final = deserialize(serialized)
        final.send :deserialize_arguments_if_needed
        final
      end
    end

    def idempotency_key
      acidic_identifier = self.class.instance_variable_get(:@acidic_identifier)
      IdempotencyKey.new(self).value(acidic_by: acidic_identifier)
    end

    # &block
    def with_acidic_workflow(persisting: {})
      raise RedefiningWorkflow if defined? @workflow_builder

      @workflow_builder = WorkflowBuilder.new
      yield @workflow_builder

      raise NoDefinedSteps if @workflow_builder.steps.empty?

      # convert the array of steps into a hash of recovery_points and next steps
      workflow = WorkflowBuilder.define_workflow(@workflow_builder.steps)

      AcidicJob.logger.log_run_event("Initializing run...", self, nil)
      @acidic_job_run = ActiveRecord::Base.transaction(isolation: :read_uncommitted) do
        run = Run.find_by(idempotency_key: idempotency_key)

        if run.present?
          run.update!(
            last_run_at: Time.current,
            locked_at: Time.current,
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

        run
      end
      AcidicJob.logger.log_run_event("Initialized run.", self, @acidic_job_run)

      Processor.new(@acidic_job_run, self).process_run
    rescue LocalJumpError
      raise MissingWorkflowBlock, "A block must be passed to `with_acidic_workflow`"
    end

    private

    def was_staged_job?
      job_id.start_with? "STG_"
    end

    def was_workflow_job?
      @acidic_job_run.present?
    end

    def was_awaited_job?
      was_staged_job? && staged_job_run.present? && staged_job_run.awaited_by.present?
    end

    def staged_job_run
      return unless was_staged_job?
      return @staged_job_run if defined? @staged_job_run

      # "STG__#{idempotency_key}__#{encoded_global_id}"
      _prefix, _idempotency_key, encoded_global_id = job_id.split("__")
      staged_job_gid = "gid://#{Base64.decode64(encoded_global_id)}"

      @staged_job_run = GlobalID::Locator.locate(staged_job_gid)
    end

    def finish_staged_job
      delete_staged_job_record
      mark_staged_run_as_finished
    end

    def reenqueue_awaited_by_job
      run = staged_job_run.awaited_by
      job = run.job
      # this needs to be explicitly set so that `was_workflow_job?` appropriately returns `true`
      job.instance_variable_set(:@acidic_job_run, run)
      # re-hydrate the `step_result` object
      step_result = staged_job_run.returning_to

      workflow = Workflow.new(run, job, step_result)
      # TODO: WRITE REGRESSION TESTS FOR PARALLEL JOB FAILING AND RETRYING THE ORIGINAL STEP
      workflow.progress_to_next_step

      # when a batch of jobs for a step succeeds, we begin processing the `AcidicJob::Run` record again
      unless run.finished?
        run.enqueue_job
      end
      AcidicJob.logger.log_run_event("Re-enqueuing parent job...", job, run)
      AcidicJob.logger.log_run_event("Re-enqueued parent job.", job, run)
    end
  end
end