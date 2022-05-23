# frozen_string_literal: true

require "active_record"
require "global_id"
require "active_support/core_ext/object/with_options"

module AcidicJob
  class Run < ActiveRecord::Base
    include GlobalID::Identification

    FINISHED_RECOVERY_POINT = "FINISHED"

    self.table_name = "acidic_job_runs"

    belongs_to :awaited_by, class_name: "AcidicJob::Run", optional: true
    has_many :batched_runs, class_name: "AcidicJob::Run", foreign_key: "awaited_by_id"

    after_create_commit :enqueue_job, if: :staged?

    serialize :serialized_job
    serialize :workflow
    serialize :returning_to
    serialize :error_object
    store :attr_accessors

    validates :staged, inclusion: { in: [true, false] } # uses database default
    validates :idempotency_key, presence: true
    validates :serialized_job, presence: true
    validates :job_class, presence: true
    validate :not_awaited_but_unstaged

    with_options unless: :staged? do
      validates :last_run_at, presence: true
      validates :recovery_point, presence: true
      validates :workflow, presence: true
    end

    scope :staged, -> { where(staged: true) }
    scope :unstaged, -> { where(staged: false) }
    scope :finished, -> { where(recovery_point: FINISHED_RECOVERY_POINT) }
    scope :running, -> { where.not(recovery_point: FINISHED_RECOVERY_POINT) }
    scope :failed, -> { where.not(error_object: nil) }
    scope :succeeded, -> { finished.merge(where(error_object: nil)) }

    def self.clear_succeeded
      # over-write any pre-existing relation queries on `recovery_point` and/or `error_object`
      to_purge = where(
        recovery_point: FINISHED_RECOVERY_POINT,
        error_object: nil
      )

      count = to_purge.count

      return 0 if count.zero?

      AcidicJob.logger.info("Deleting #{count} successfully completed AcidicJob runs")
      to_purge.delete_all
    end

    def job
      serialized_job_for_run = serialized_job.merge("job_id" => job_id)
      job_class_for_run = job_class.constantize
      job_class_for_run.deserialize(serialized_job_for_run)
    end

    def awaited?
      awaited_by.present?
    end

    def workflow?
      workflow.present?
    end

    def succeeded?
      finished? && !failed?
    end

    def finished?
      recovery_point.to_s == FINISHED_RECOVERY_POINT
    end

    def failed?
      error_object.present?
    end

    def known_recovery_point?
      workflow.key?(recovery_point)
    end

    def attr_accessors
      self[:attr_accessors] || {}
    end

    def enqueue_job
      job.enqueue

      # NOTE: record will be deleted after the job has successfully been performed
      true
    end

    private

    def not_awaited_but_unstaged
      return true unless awaited? && !staged?

      errors.add(:base, "cannot be awaited by another job but not staged")
    end

    def job_id
      return idempotency_key unless staged?

      # encode the identifier for this record in the job ID
      global_id = to_global_id.to_s.remove("gid://")
      # base64 encoding for minimal security
      encoded_global_id = Base64.encode64(global_id).strip
      "STG__#{idempotency_key}__#{encoded_global_id}"
    end
  end
end
