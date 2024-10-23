# frozen_string_literal: true

module AcidicJob
  class Value < Record
    self.table_name = "acidic_job_values"

    belongs_to :execution, class_name: "AcidicJob::Execution"

    serialize :value, coder: AcidicJob::Serializer
  end
end