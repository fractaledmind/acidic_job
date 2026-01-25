# frozen_string_literal: true

module AcidicJob
  class Execution < ApplicationRecord
    has_many :entries, class_name: "AcidicJob::Entry", dependent: :destroy
    has_many :values, class_name: "AcidicJob::Value", dependent: :destroy

    serialize :definition, coder: AcidicJob::Serializer

    validates :idempotency_key, presence: true # uniqueness constraint is enforced at the database level
    validates :serialized_job, presence: true

    scope :finished, -> {
      where(recover_to: FINISHED_RECOVERY_POINT)
    }
    scope :outstanding, -> {
      where.not(recover_to: FINISHED_RECOVERY_POINT).or(where(recover_to: [ nil, "" ]))
    }
    scope :clearable, ->(finished_before: AcidicJob.clear_finished_executions_after.ago) {
      finished.where(last_run_at: ...finished_before)
    }

    def self.clear_finished_in_batches(batch_size: 500, finished_before: AcidicJob.clear_finished_executions_after.ago, sleep_between_batches: 0)
      loop do
        records_deleted = clearable(finished_before: finished_before).limit(batch_size).delete_all
        sleep(sleep_between_batches) if sleep_between_batches > 0
        break if records_deleted == 0
      end
    end

    def record!(step:, action:, timestamp: Time.current, **kwargs)
      AcidicJob.instrument(:record_entry, step: step, action: action, timestamp: timestamp, data: kwargs) do
        entries.insert!({
          step: step,
          action: action,
          timestamp: timestamp,
          data: kwargs.except(:ignored)
        })
      end
    end

    def context
      @context ||= Context.new(self)
    end

    def finished?
      if recover_to.to_s == "FINISHED"
        unless defined?(@finished_deprecation_warned) && @finished_deprecation_warned
          AcidicJob.deprecator.warn(
            "The 'FINISHED' recovery point value is deprecated and will be removed in AcidicJob 1.1. " \
            "Executions should use the new '#{FINISHED_RECOVERY_POINT}' value.",
            caller_locations(1)
          )
          @finished_deprecation_warned = true
        end
        return true
      end

      recover_to.to_s == FINISHED_RECOVERY_POINT
    end

    def defined?(step)
      if definition.key?("steps")
        definition["steps"].key?(step)
      else
        AcidicJob.deprecator.warn(
          "Workflow definitions without a 'steps' key are deprecated and will be removed in AcidicJob 1.1. " \
          "Please update your workflow to use the new format.",
          caller_locations(1)
        )
        definition.key?(step)
      end
    end

    def definition_for(step)
      if definition.key?("steps")
        definition["steps"].fetch(step)
      else
        AcidicJob.deprecator.warn(
          "Workflow definitions without a 'steps' key are deprecated and will be removed in AcidicJob 1.1. " \
          "Please update your workflow to use the new format.",
          caller_locations(1)
        )
        definition.fetch(step)
      end
    end

    def deserialized_job
      serialized_job["job_class"].constantize.new.tap do |job|
        job.deserialize(serialized_job)
      end
    end

    def raw_arguments
      JSON.parse(serialized_job_before_type_cast)["arguments"]
    end

    def enqueue_job
      deserialized_job.enqueue
      true
    end
  end
end
