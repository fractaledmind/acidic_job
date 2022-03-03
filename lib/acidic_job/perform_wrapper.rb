# frozen_string_literal: true

module AcidicJob
  # NOTE: it is essential that this be a bare module and not an ActiveSupport::Concern
  module PerformWrapper
    def perform(*args, **kwargs)
      super_method = method(:perform).super_method

      # we don't want to run the `perform` callbacks twice, since ActiveJob already handles that for us
      if aj_job?
        __acidic_job_perform_for_aj(super_method, *args, **kwargs)
      elsif sk_job?
        __acidic_job_perform_for_sk(super_method, *args, **kwargs)
      else
        raise UnknownJobAdapter
      end
    end

    def sk_job?
      defined?(Sidekiq) && self.class.include?(Sidekiq::Worker)
    end

    def aj_job?
      defined?(ActiveJob) && self.class < ActiveJob::Base
    end

    private

    # don't run `perform` callbacks, as ActiveJob already does this
    def __acidic_job_perform_for_aj(super_method, *args, **kwargs)
      __acidic_job_perform_base(super_method, *args, **kwargs)
    end

    # ensure to run `perform` callbacks
    def __acidic_job_perform_for_sk(super_method, *args, **kwargs)
      run_callbacks :perform do
        __acidic_job_perform_base(super_method, *args, **kwargs)
      end
    end

    # capture arguments passed to `perform` to be used by AcidicJob later
    def __acidic_job_perform_base(super_method, *args, **kwargs)
      @__acidic_job_args = args
      @__acidic_job_kwargs = kwargs

      super_method.call(*args, **kwargs)
    end
  end
end
