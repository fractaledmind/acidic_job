# frozen_string_literal: true

module AcidicJob
  class Entry < ApplicationRecord
    belongs_to :execution, class_name: "AcidicJob::Execution"

    serialize :data, coder: AcidicJob::Serializer

    scope :for_step, ->(step) { where(step: step) }
    scope :for_action, ->(action) { where(action: action) }
    scope :ordered, -> { order(timestamp: :asc, created_at: :asc) }

    def self.most_recent
      order(created_at: :desc).first
    end

    def action?(check)
      action == check
    end
  end
end
