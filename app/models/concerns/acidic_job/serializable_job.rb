# frozen_string_literal: true

module AcidicJob
  module SerializableJob
    extend ActiveSupport::Concern

    included do
      validates :serialized_job, presence: true

      serialize :serialized_job, coder: AcidicJob::Serializer
    end

    def deserialized_job
      serialized_job["job_class"].constantize.new.yield_self do |job|
        job.deserialize(serialized_job)
      end
    end

    def enqueue_job
      deserialized_job.enqueue

      true
    end
  end
end
