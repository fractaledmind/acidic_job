# frozen_string_literal: true

module AcidicJob
  class BatchedJob < Record
    self.table_name = "acidic_job_batched_jobs"

    include SerializableJob

    belongs_to :execution, class_name: "AcidicJob::Execution"

    validates :job_id, presence: true
    validates :progress_to, presence: true

    after_update_commit :proceed_with_execution

    scope :outstanding, lambda { where(performed_at: [nil, ""]) }

    def performed? = performed_at.present?

    def proceed_with_execution
      return unless performed?
      return unless execution.present?
      return if execution.batched_jobs.outstanding.any?

      # execution.unlock!
      execution.proceed_to(progress_to)
    end
  end
end