# frozen_string_literal: true

require "active_record"
require "global_id"
require "active_support/core_ext/object/with_options"

module AcidicJob
  class Run < ActiveRecord::Base
    include GlobalID::Identification

    FINISHED_RECOVERY_POINT = "FINISHED"

    self.table_name = "acidic_job_runs"

    after_create_commit :enqueue_staged_job, if: :staged?

    serialize :error_object
    serialize :serialized_job
    serialize :workflow
    store :attr_accessors

    validates :staged, inclusion: { in: [true, false] } # uses database default
    validates :serialized_job, presence: true
    validates :idempotency_key, presence: true, uniqueness: true
    validates :job_class, presence: true

    scope :staged, -> { where(staged: true) }
    scope :unstaged, -> { where(staged: false) }
    scope :finished, -> { where(recovery_point: FINISHED_RECOVERY_POINT) }
    scope :running, -> { where.not(recovery_point: FINISHED_RECOVERY_POINT) }

    with_options unless: :staged? do
      validates :last_run_at, presence: true
      validates :recovery_point, presence: true
      validates :workflow, presence: true
    end

    def self.purge
      successfully_completed = where(
        recovery_point: FINISHED_RECOVERY_POINT,
        error_object: nil
      )
      count = successfully_completed.count

      return 0 if count.zero?

      Rails.logger.info("Deleting #{count} successfully completed AcidicJob runs")
      successfully_completed.delete_all
    end

    def finished?
      recovery_point == FINISHED_RECOVERY_POINT
    end

    def succeeded?
      finished? && !failed?
    end

    def failed?
      error_object.present?
    end

    private

    def enqueue_staged_job
      return unless staged?

      # encode the identifier for this record in the job ID
      # base64 encoding for minimal security
      global_id = to_global_id.to_s.remove("gid://")
      encoded_global_id = Base64.encode64(global_id).strip
      staged_job_id = "STG_#{idempotency_key}__#{encoded_global_id}"

      serialized_staged_job = if serialized_job.key?("jid")
                                serialized_job.merge("jid" => staged_job_id)
                              elsif serialized_job.key?("job_id")
                                serialized_job.merge("job_id" => staged_job_id)
                              else
                                raise UnknownSerializedJobIdentifier
                              end

      job = job_class.constantize.deserialize(serialized_staged_job)

      job.enqueue

      # NOTE: record will be deleted after the job has successfully been performed
      true
    end
  end
end
