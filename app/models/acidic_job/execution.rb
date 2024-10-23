# frozen_string_literal: true

module AcidicJob
  class Execution < Record
    self.table_name = "acidic_job_executions"

    include SerializableJob

    has_many :entries, class_name: "AcidicJob::Entry"
    has_many :values, class_name: "AcidicJob::Value"
    has_many :batched_jobs, class_name: "AcidicJob::BatchedJob"

    validates :idempotency_key, presence: true, uniqueness: true

    serialize :definition, coder: AcidicJob::Serializer

    scope :finished, -> { where(recover_to: FINISHED_RECOVERY_POINT) }
    scope :outstanding, lambda {
                          where.not(recover_to: FINISHED_RECOVERY_POINT).or(where(recover_to: [nil, ""]))
                        }

    def record!(step:, action:, timestamp:, **kwargs)
      entries.create!(
        step: step,
        action: action,
        timestamp: timestamp,
        data: kwargs.stringify_keys!
      )
    end

    def recover_to_step
      step, _cursor = recover_to.split(":")
      step
    end

    def recover_to_cursor
      _step, cursor = recover_to.split(":")
      cursor.to_i
    end

    def finished?
      recover_to.to_s == FINISHED_RECOVERY_POINT
    end

    def proceed_to(recovery_point)
      # TODO: write regression tests for parallel job failing and retrying the original step
      update!(recover_to: recovery_point)

      return if finished?

      enqueue_job
    end
  end
end