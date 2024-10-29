# frozen_string_literal: true

module AcidicJob
  class Entry < Record
    belongs_to :execution, class_name: "AcidicJob::Execution"

    def started? = action == "started"
    def succeeded? = action == "succeeded"
    def errored? = action == "errored"
  end
end