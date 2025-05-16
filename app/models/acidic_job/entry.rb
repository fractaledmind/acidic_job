# frozen_string_literal: true

module AcidicJob
  class Entry < Record
    belongs_to :execution, class_name: "AcidicJob::Execution"

    scope :for_step, ->(step) { where(step: step) }
    scope :for_action, ->(action) { where(action: action) }
    scope :ordered, -> { order(timestamp: :asc) }

    def self.most_recent = order(created_at: :desc).first

    def is_action?(check) = self.action == check
  end
end
