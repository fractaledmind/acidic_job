# frozen_string_literal: true

require "active_record"
require "global_id"

module AcidicJob
  class Staged < ActiveRecord::Base
    self.table_name = "staged_acidic_jobs"

    include GlobalID::Identification

    validates :adapter, presence: true
    validates :job_name, presence: true
    validates :job_args, presence: true

    serialize :job_args

    after_create_commit :enqueue_job

    def enqueue_job
      gid = {"staged_job_gid" => self.to_global_id.to_s}

      if job_args.is_a?(Hash) && job_args.key?("arguments")
        job_args["arguments"].concat([gid])
      else
        job_args.concat([gid])
      end

      case adapter
      when "activejob"
        job = ActiveJob::Base.deserialize(job_args)
        job.enqueue
      when "sidekiq"
        Sidekiq::Client.push(
          "class" => job_name,
          "args" => job_args,
        )
      else
        raise UnknownJobAdapter.new(adapter: adapter)
      end

      # NOTE: record will be deleted after the job has successfully been performed
      true
    end
  end
end
