# frozen_string_literal: true

require "active_record"
require "global_id"
require "active_support/core_ext/object/with_options"

module AcidicJob
  class Run < ActiveRecord::Base
    include GlobalID::Identification

    FINISHED_RECOVERY_POINT = "FINISHED"
    STAGED_JOB_ID_PREFIX = "STG"
    STAGED_JOB_ID_DELIMITER = "__"

    self.table_name = "acidic_job_runs"

    belongs_to :awaited_by, class_name: "AcidicJob::Run", optional: true
    has_many :batched_runs, class_name: "AcidicJob::Run", foreign_key: "awaited_by_id"

    after_create_commit :enqueue_job, if: :staged?
    after_update_commit :proceed_with_parent, if: :finished?

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
    scope :outstanding, -> { where.not(recovery_point: FINISHED_RECOVERY_POINT).or(where(recovery_point: [nil, ""])) }
    scope :errored, -> { where.not(error_object: nil) }

    def finish!
      self.recovery_point = FINISHED_RECOVERY_POINT
      unlock.save!
    end

    def unlock
      self.locked_at = nil
      self
    end

    def self.clear_finished
      # over-write any pre-existing relation queries on `recovery_point` and/or `error_object`
      to_purge = finished

      count = to_purge.count

      return 0 if count.zero?

      AcidicJob.logger.info("Deleting #{count} finished AcidicJob runs")
      to_purge.delete_all
    end

    def proceed_with_parent
      return unless finished?
      return unless awaited_by.present?
      return if awaited_by.batched_runs.outstanding.any?

      awaited_by.proceed
    end

    def proceed
      AcidicJob.logger.log_run_event("Proceeding with parent job...", job, self)
      # this needs to be explicitly set so that `was_workflow_job?` appropriately returns `true`
      # TODO: replace this with some way to check the type of the job directly
      # either via class method or explicit module inclusion
      job.instance_variable_set(:@acidic_job_run, self)

      # re-hydrate the `step_result` object
      step_result = returning_to

      workflow = Workflow.new(self, job, step_result)
      # TODO: WRITE REGRESSION TESTS FOR PARALLEL JOB FAILING AND RETRYING THE ORIGINAL STEP
      workflow.progress_to_next_step

      AcidicJob.logger.log_run_event("Proceeded with parent job.", job, self)
      # when a batch of jobs for a step succeeds, we begin processing the `AcidicJob::Run` record again
      return if finished?

      AcidicJob.logger.log_run_event("Re-enqueuing parent job...", job, self)
      enqueue_job
      AcidicJob.logger.log_run_event("Re-enqueued parent job.", job, self)
    end

    def job
      return @job if defined? @job

      serialized_job_for_run = serialized_job.merge("job_id" => job_id)
      job_class_for_run = job_class.constantize

      @job = job_class_for_run.deserialize(serialized_job_for_run)
    end

    def awaited?
      awaited_by.present?
    end

    def workflow?
      workflow.present?
    end

    def succeeded?
      finished? && !errored?
    end

    def finished?
      recovery_point.to_s == FINISHED_RECOVERY_POINT
    end

    def errored?
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

      [
        STAGED_JOB_ID_PREFIX,
        idempotency_key,
        encoded_global_id
      ].join(STAGED_JOB_ID_DELIMITER)
    end
  end
end
