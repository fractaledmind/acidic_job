module AcidicJob
  class Staging < ActiveRecord::Base
    self.table_name = "acidic_job_stagings"

    validates :serialized_params, presence: true

    serialize :serialized_params

    after_create_commit :enqueue_job

    def enqueue_job
      job = ActiveJob::Base.deserialize(serialized_params)
      job.enqueue
    end
  end
end
