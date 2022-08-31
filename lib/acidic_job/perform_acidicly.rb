# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module PerformAcidicly
    extend ActiveSupport::Concern

    # `perform_now` runs a job synchronously and immediately
    # `perform_later` runs a job asynchronously and queues it immediately
    # `perform_acidicly` run a job asynchronously and queues it after a successful database commit

    class_methods do
      def perform_acidicly(...)
        job_or_instantiate(...).perform_acidicly
      end
    end

    def perform_acidicly
      Run.stage!(self)
    end
  end
end
