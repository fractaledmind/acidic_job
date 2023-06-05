# frozen_string_literal: true

require "active_record"
require "global_id"
require "base64"
require "active_support/core_ext/object/with_options"
require "active_support/core_ext/module/concerning"
require "active_support/concern"

module AcidicJob
  class Run < ActiveRecord::Base
    include GlobalID::Identification

    FINISHED_RECOVERY_POINT = "FINISHED"
    STAGED_JOB_ID_PREFIX = "STG"
    STAGED_JOB_ID_DELIMITER = "__"
    IDEMPOTENCY_KEY_LOCK_TIMEOUT_SECONDS = 2

    self.table_name = "acidic_job_runs"

    validates :idempotency_key, presence: true
    validate :not_awaited_but_unstaged

    def self.clear_finished
      # over-write any pre-existing relation queries on `recovery_point` and/or `error_object`
      to_purge = finished

      count = to_purge.count

      return 0 if count.zero?

      AcidicJob.logger.info("Deleting #{count} finished AcidicJob runs")
      to_purge.delete_all
    end

    def succeeded?
      finished? && !errored?
    end

    concerning :Awaitable do
      included do
        belongs_to :awaited_by, class_name: "AcidicJob::Run", optional: true
        has_many :batched_runs, class_name: "AcidicJob::Run", foreign_key: "awaited_by_id"

        scope :awaited, -> { where.not(awaited_by: nil) }
        scope :unawaited, -> { where(awaited_by: nil) }

        after_update_commit :proceed_with_parent, if: :finished?

        serialize :returning_to, coder: AcidicJob::Serializer
      end

      class_methods do
        def await!(job, by:, return_to:)
          create!(
            staged: true,
            awaited_by: by,
            job_class: job.class.name,
            serialized_job: job.serialize,
            idempotency_key: job.idempotency_key
          )
          by.update(returning_to: return_to)
        end
      end

      def awaited?
        awaited_by.present?
      end

      private

      def proceed_with_parent
        return unless finished?
        return unless awaited_by.present?
        return if awaited_by.batched_runs.outstanding.any?

        AcidicJob.logger.log_run_event("Proceeding with parent job...", job, self)
        awaited_by.unlock!
        awaited_by.proceed
        AcidicJob.logger.log_run_event("Proceeded with parent job.", job, self)
      end

      protected

      def proceed
        # this needs to be explicitly set so that `was_workflow_job?` appropriately returns `true`
        # TODO: replace this with some way to check the type of the job directly
        # either via class method or explicit module inclusion
        job.instance_variable_set(:@acidic_job_run, self)

        workflow = Workflow.new(self, job, returning_to)
        # TODO: WRITE REGRESSION TESTS FOR PARALLEL JOB FAILING AND RETRYING THE ORIGINAL STEP
        workflow.progress_to_next_step

        # when a batch of jobs for a step succeeds, we begin processing the `AcidicJob::Run` record again
        return if finished?

        AcidicJob.logger.log_run_event("Re-enqueuing parent job...", job, self)
        enqueue_job
        AcidicJob.logger.log_run_event("Re-enqueued parent job.", job, self)
      end
    end

    concerning :Stageable do
      included do
        after_create_commit :enqueue_job, if: :staged?

        validates :staged, inclusion: { in: [true, false] } # uses database default

        scope :staged, -> { where(staged: true) }
        scope :unstaged, -> { where(staged: false) }
      end

      class_methods do
        def stage!(job)
          create!(
            staged: true,
            job_class: job.class.name,
            serialized_job: job.serialize,
            idempotency_key: job.try(:idempotency_key) || job.job_id
          )
        end
      end

      private

      def job_id
        return idempotency_key unless staged?

        # encode the identifier for this record in the job ID
        global_id = to_global_id.to_s.remove("gid://")
        # base64 encoding for minimal security
        encoded_global_id = Base64.urlsafe_encode64(global_id, padding: false)

        [
          STAGED_JOB_ID_PREFIX,
          idempotency_key,
          encoded_global_id
        ].join(STAGED_JOB_ID_DELIMITER)
      end
    end

    concerning :Workflowable do
      included do
        serialize :workflow, coder: AcidicJob::Serializer
        serialize :error_object, coder: AcidicJob::Serializer
        store :attr_accessors, coder: AcidicJob::Serializer

        with_options unless: :staged? do
          validates :last_run_at, presence: true
          validates :recovery_point, presence: true
          validates :workflow, presence: true
        end
      end

      def workflow?
        self[:workflow].present?
      end

      def attr_accessors
        self[:attr_accessors] || {}
      end

      def current_step_name
        recovery_point
      end

      def current_step_hash
        workflow[current_step_name]
      end

      def next_step_name
        current_step_hash.fetch("then")
      end

      def current_step_awaits
        current_step_hash["awaits"]
      end

      def next_step_finishes?
        next_step_name.to_s == FINISHED_RECOVERY_POINT
      end

      def current_step_finished?
        current_step_name.to_s == FINISHED_RECOVERY_POINT
      end
    end

    concerning :Jobbable do
      included do
        serialize :serialized_job, coder: JSON

        validates :serialized_job, presence: true
        validates :job_class, presence: true
      end

      def job
        return @job if defined? @job

        serialized_job_for_run = serialized_job.merge("job_id" => job_id)
        job_class_for_run = job_class.constantize

        @job = job_class_for_run.deserialize(serialized_job_for_run)
      end

      def enqueue_job
        job.enqueue

        # NOTE: record will be deleted after the job has successfully been performed
        true
      end
    end

    concerning :Finishable do
      included do
        scope :finished, -> { where(recovery_point: FINISHED_RECOVERY_POINT) }
        scope :outstanding, lambda {
                              where.not(recovery_point: FINISHED_RECOVERY_POINT).or(where(recovery_point: [nil, ""]))
                            }
      end

      def finish!
        finish and unlock and save!
      end

      def finish
        self.recovery_point = FINISHED_RECOVERY_POINT
        self
      end

      def finished?
        recovery_point.to_s == FINISHED_RECOVERY_POINT
      end
    end

    concerning :Unlockable do
      included do
        scope :unlocked, -> { where(locked_at: nil) }
        scope :locked, -> { where.not(locked_at: nil) }
      end

      def unlock!
        unlock and save!
      end

      def unlock
        self.locked_at = nil
        self
      end

      def locked?
        locked_at.present?
      end

      def lock_active?
        return false if locked_at.nil?

        locked_at > Time.current - IDEMPOTENCY_KEY_LOCK_TIMEOUT_SECONDS
      end
    end

    concerning :ErrorStoreable do
      included do
        scope :unerrored, -> { where(error_object: nil) }
        scope :errored, -> { where.not(error_object: nil) }
      end

      def store_error!(error)
        reload and unlock and store_error(error) and save!
      end

      def store_error(error)
        self.error_object = error
        self
      end

      def errored?
        error_object.present?
      end
    end

    concerning :Recoverable do
      def recover_to!(point)
        recover_to(point) and save!
      end

      def recover_to(point)
        self.recovery_point = point
        self
      end

      def known_recovery_point?
        workflow.key?(recovery_point)
      end
    end

    def not_awaited_but_unstaged
      return true unless awaited? && !staged?

      errors.add(:base, "cannot be awaited by another job but not staged")
    end
  end
end
