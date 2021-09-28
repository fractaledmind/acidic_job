# frozen_string_literal: true

require "active_record"

module AcidicJob
  class Staged < ActiveRecord::Base
    self.table_name = "staged_acidic_jobs"

    validates :adapter, presence: true
    validates :job_name, presence: true
    validates :job_args, presence: true

    serialize :job_args

    after_create_commit :enqueue_job

    def enqueue_job
      if adapter == "activejob"
        job = ActiveJob::Base.deserialize(job_args)
        job.enqueue
      elsif adapter == "sidekiq"
        Sidekiq::Client.push("class" => job_name, "args" => job_args)
      else
      end

      delete
    end
  end
end
