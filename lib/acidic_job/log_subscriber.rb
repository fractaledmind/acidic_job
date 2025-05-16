# frozen_string_literal: true

require "active_support/log_subscriber"

module AcidicJob
  class LogSubscriber < ActiveSupport::LogSubscriber
    def define_workflow(event)
      debug formatted_event(event, title: "Define workflow", **event.payload.slice(:job_class, :job_id))
    end

    def initialize_workflow(event)
      debug formatted_event(event, title: "Initialize workflow", **event.payload.slice(:steps))
    end

    def process_workflow(event)
      debug formatted_event(event, title: "Process workflow", **event.payload[:execution].slice(:id, :recover_to))
    end

    def process_step(event)
      debug formatted_event(event, title: "Process step", **event.payload)
    end

    def perform_step(event)
      debug formatted_event(event, title: "Perform step", **event.payload)
    end

    def record_entry(event)
      debug formatted_event(event, title: "Record entry", **event.payload.slice(:step, :action, :timestamp))
    end

    private

    def formatted_event(event, title:, **attributes)
      "AcidicJob-#{AcidicJob::VERSION} #{title} (#{event.duration.round(1)}ms)  #{formatted_attributes(**attributes)}"
    end

    def formatted_attributes(**attributes)
      attributes.map { |attr, value| "#{attr}: #{value.inspect}" }.join(", ")
    end

    def formatted_error(error)
      [error.class, error.message].compact.join(" ")
    end

    # Use the logger configured for AcidicJob
    def logger
      AcidicJob.logger
    end
  end
end
