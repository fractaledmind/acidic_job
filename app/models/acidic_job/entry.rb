# frozen_string_literal: true

module AcidicJob
  class Entry < Record
    self.table_name = "acidic_job_entries"

    belongs_to :execution, class_name: "AcidicJob::Execution"

    serialize :data, coder: AcidicJob::Serializer

    # action enum:
    # :skipped
    # :succeeded
    # :retried
    # :started
    # :iterated
    # :completed
    # :compensated
    # :errored
  end
end