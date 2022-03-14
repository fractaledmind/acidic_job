# frozen_string_literal: true

module AcidicJob
  class IdempotencyKey
    def initialize(identifier = :job_id)
      @identifier = identifier
    end

    def value_for(hash_or_job, *args, **kwargs)
      value = case @identifier
              when Proc
                value_from_proc(hash_or_job, *args, **kwargs)
              when :job_args
                value_from_job_args(hash_or_job, *args, **kwargs)
              else
                if hash_or_job.is_a?(Hash)
                  value_from_job_id_for_hash(hash_or_job)
                else
                  value_from_job_id_for_obj(hash_or_job)
                end
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

    def value_from_proc(_hash_or_job, *args, **kwargs)
      return if args.empty? && kwargs.empty?

      idempotency_args = Array(@identifier.call(*args, **kwargs))
      Digest::SHA1.hexdigest idempotency_args.flatten.join
    end
  end
end
