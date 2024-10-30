# frozen_string_literal: true

module AcidicJob
  class Execution < Record
    has_many :entries, class_name: "AcidicJob::Entry"
    has_many :values, class_name: "AcidicJob::Value"

    validates :idempotency_key, presence: true # uniqueness constraint is enforced at the database level
    validates :serialized_job, presence: true

    scope :finished, -> { where(recover_to: FINISHED_RECOVERY_POINT) }
    scope :outstanding, lambda {
                          where.not(recover_to: FINISHED_RECOVERY_POINT).or(where(recover_to: [nil, ""]))
                        }

    def record!(step:, action:, timestamp:, **kwargs)
      AcidicJob.instrument(:record_entry, step: step, action: action, timestamp: timestamp, data: kwargs) do
        entries.create!(
          step: step,
          action: action,
          timestamp: timestamp,
          data: kwargs.stringify_keys!
        )
      end
    end

    def context
      @context ||= Context.new(self)
    end

    def finished?
      recover_to.to_s == FINISHED_RECOVERY_POINT
    end

    def deserialized_job
      serialized_job["job_class"].constantize.new.tap do |job|
        job.deserialize(serialized_job)
      end
    end

    def raw_arguments
      JSON.parse(serialized_job_before_type_cast)["arguments"]
    end
  end
end
