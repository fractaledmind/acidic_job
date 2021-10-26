# frozen_string_literal: true

module AcidicJob
  module PerformWrapper
    def perform(*args, **kwargs)
      # extract the `staged_job_gid` if present
      # so that we can later delete the record in an `after_perform` callback
      final_arg = args.last
      if final_arg.is_a?(Hash) && final_arg.key?("staged_job_gid")
        args = args[0..-2]
        @staged_job_gid = final_arg["staged_job_gid"]
      end

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

      super(*args, **kwargs)
    end
  end
end
