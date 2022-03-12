# frozen_string_literal: true

module AcidicJob
  class IdempotencyKey
    def self.value_for(hash_or_job)
      new(hash_or_job).value_for(:job_id)
    end

    def initialize(hash_or_job)
      @hash_or_job = hash_or_job
    end

    def value_for(unique_by)
      value = if @hash_or_job.is_a?(Hash)
                value_from_job_id_for_hash
              else
                value_from_job_id_for_obj
              end
      # p ['***', value, unique_by]
      return value if unique_by == :job_id && value.present?

      value_from_job_args(unique_by)
    end

    private

    def value_from_job_id_for_hash
      if @hash_or_job.key?("job_id")
        return if @hash_or_job["job_id"].nil?
        return if @hash_or_job["job_id"].empty?

        @hash_or_job["job_id"]
      elsif @hash_or_job.key?("jid")
        return if @hash_or_job["jid"].nil?
        return if @hash_or_job["jid"].empty?

        @hash_or_job["jid"]
      end
    end

    def value_from_job_id_for_obj
      if @hash_or_job.respond_to?(:job_id)
        return if @hash_or_job.job_id.nil?
        return if @hash_or_job.job_id.empty?

        @hash_or_job.job_id
      elsif @hash_or_job.respond_to?(:jid)
        return if @hash_or_job.jid.nil?
        return if @hash_or_job.jid.empty?

        @hash_or_job.jid
      end
    end

    def value_from_job_args(user_defined_uniqueness)
      worker_class = if @hash_or_job.is_a?(Hash)
                       @hash_or_job["worker"] || @hash_or_job["job_class"]
                     else
                       @hash_or_job.class.name
                     end
      uniqueness = Marshal.dump(user_defined_uniqueness)

      Digest::SHA1.hexdigest [worker_class, uniqueness].join("-")
    end
  end
end
