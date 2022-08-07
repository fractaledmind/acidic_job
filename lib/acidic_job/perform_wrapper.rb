# frozen_string_literal: true

module AcidicJob
  # NOTE: it is essential that this be a bare module and not an ActiveSupport::Concern
  # WHY?
  module PerformWrapper
    def perform(*args, **kwargs)
      @arguments = args

      # we don't want to run the `perform` callbacks twice, since ActiveJob already handles that for us
      if defined?(ActiveJob) && self.class < ActiveJob::Base
        super(*args, **kwargs)
      elsif defined?(Sidekiq) && self.class.include?(Sidekiq::Worker)
        run_callbacks :perform do
          super(*args, **kwargs)
        end
      else
        raise UnknownJobAdapter
      end
    end
  end
end
