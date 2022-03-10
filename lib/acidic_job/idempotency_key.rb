# frozen_string_literal: true

module AcidicJob
  class IdempotencyKey
    def self.value_for(hash_or_job, *args, **kwargs)
      new(:job_id).value_for(hash_or_job, *args, **kwargs)
    end

    def initialize(identifier)
      @identifier = identifier
    end

    def value_for(hash_or_job, *args, **kwargs)
      return value_from_job_args(hash_or_job, *args, **kwargs) if @identifier == :job_args

      value = if hash_or_job.is_a?(Hash)
                value_from_job_id_for_hash(hash_or_job)
              else
                value_from_job_id_for_obj(hash_or_job)
              end

      value || value_from_job_args(hash_or_job, *args, **kwargs)
    end

    private

    def value_from_job_id_for_hash(hash)
      if hash.key?("job_id")
        return if hash["job_id"].nil?
        return if hash["job_id"].empty?

        hash["job_id"]
      elsif hash.key?("jid")
        return if hash["jid"].nil?
        return if hash["jid"].empty?

        hash["jid"]
      end
    end

    def value_from_job_id_for_obj(obj)
      if obj.respond_to?(:job_id)
        return if obj.job_id.nil?
        return if obj.job_id.empty?

        obj.job_id
      elsif obj.respond_to?(:jid)
        return if obj.jid.nil?
        return if obj.jid.empty?

        obj.jid
      end
    end

    def value_from_job_args(hash_or_job, *args, **kwargs)
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
