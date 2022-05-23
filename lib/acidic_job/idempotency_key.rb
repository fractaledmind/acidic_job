# frozen_string_literal: true

module AcidicJob
  class IdempotencyKey
    def initialize(job)
      @job = job
    end
  
    def value(acidic_by: :job_id)
      case acidic_by
      when Proc
        proc_result = @job.instance_exec(&acidic_by)
        Digest::SHA1.hexdigest [@job.class.name, proc_result].flatten.join
      when :job_arguments
        Digest::SHA1.hexdigest [@job.class.name, @job.arguments].flatten.join
      else
        if @job.job_id.start_with? "STG_"
          # "STG__#{idempotency_key}__#{encoded_global_id}"
          _prefix, idempotency_key, _encoded_global_id = @job.job_id.split("__")
          idempotency_key
        else
          @job.job_id
        end
      end
    end
  end
end
