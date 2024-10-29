# frozen_string_literal: true

module AcidicJob
  class Value < Record
    belongs_to :execution, class_name: "AcidicJob::Execution"
  end
end