# frozen_string_literal: true

module AcidicJob
  class IdempotencyKey
    def self.value_for(hash_or_job, *args, **kwargs)
      return hash_or_job.job_id if hash_or_job.respond_to?(:job_id) && !hash_or_job.job_id.nil?
      return hash_or_job.jid if hash_or_job.respond_to?(:jid) && !hash_or_job.jid.nil?

      if hash_or_job.is_a?(Hash) && hash_or_job.key?("job_id") && !hash_or_job["job_id"].nil?
        return hash_or_job["job_id"]
      end
      return hash_or_job["jid"] if hash_or_job.is_a?(Hash) && hash_or_job.key?("jid") && !hash_or_job["jid"].nil?

      worker_class = case hash_or_job
                     when Hash
                       hash_or_job["worker"] || hash_or_job["job_class"]
                     else
                       hash_or_job.class.name
                     end

      Digest::SHA1.hexdigest [worker_class, args, kwargs].flatten.join
    end
  end
end
