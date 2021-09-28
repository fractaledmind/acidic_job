# frozen_string_literal: true

module AcidicJob
  module PerformWrapper
    def perform(*args, **kwargs)
      # store arguments passed into `perform` so that we can later persist
      # them to `AcidicJob::Key#job_args` for both ActiveJob and Sidekiq::Worker
      @arguments_for_perform = if args.any? && kwargs.any?
        args + [kwargs]
      elsif args.any? && kwargs.none?
        args
      elsif args.none? && kwargs.any?
        [kwargs]
      else
        []
      end

      super
    end
  end
end
