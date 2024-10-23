# frozen_string_literal: true

require "active_support/log_subscriber"

module AcidicJob
  class LogSubscriber < ActiveSupport::LogSubscriber
    # initialize_execution

    def dispatch_scheduled(event)
      debug formatted_event(event, action: "Dispatch scheduled jobs", **event.payload.slice(:batch_size, :size))
    end

    def release_many_claimed(event)
      info formatted_event(event, action: "Release claimed jobs", **event.payload.slice(:size))
    end

    def fail_many_claimed(event)
      warn formatted_event(event, action: "Fail claimed jobs", **event.payload.slice(:job_ids, :process_ids))
    end

    def enqueue_recurring_task(event)
      attributes = event.payload.slice(:task, :active_job_id, :enqueue_error)
      attributes[:at] = event.payload[:at]&.iso8601

      if attributes[:active_job_id].nil? && event.payload[:skipped].nil?
        error formatted_event(event, action: "Error enqueuing recurring task", **attributes)
      elsif event.payload[:other_adapter]
        debug formatted_event(event, action: "Enqueued recurring task outside Solid Queue", **attributes)
      else
        action = event.payload[:skipped].present? ? "Skipped recurring task – already dispatched" : "Enqueued recurring task"
        debug formatted_event(event, action: action, **attributes)
      end
    end

    def register_process(event)
      process_kind = event.payload[:kind]
      attributes = event.payload.slice(:pid, :hostname, :process_id, :name)

      if error = event.payload[:error]
        warn formatted_event(event, action: "Error registering #{process_kind}", **attributes.merge(error: formatted_error(error)))
      else
        debug formatted_event(event, action: "Register #{process_kind}", **attributes)
      end
    end

    private
      def formatted_event(event, action:, **attributes)
        "AcidicJob-#{AcidicJob::VERSION} #{action} (#{event.duration.round(1)}ms)  #{formatted_attributes(**attributes)}"
      end

      def formatted_attributes(**attributes)
        attributes.map { |attr, value| "#{attr}: #{value.inspect}" }.join(", ")
      end

      def formatted_error(error)
        [ error.class, error.message ].compact.join(" ")
      end

      # Use the logger configured for AcidicJob
      def logger
        AcidicJob.logger
      end
  end
end