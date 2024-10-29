# frozen_string_literal: true

module AcidicJob
  class Engine < ::Rails::Engine
    isolate_namespace AcidicJob

    config.acidic_job = ActiveSupport::OrderedOptions.new

    initializer "acidic_job.config" do
      config.acidic_job.each do |name, value|
        AcidicJob.public_send("#{name}=", value)
      end
    end

    initializer "acidic_job.logger" do
      ActiveSupport.on_load :acidic_job do
        self.logger = ::Rails.logger if logger == AcidicJob::DEFAULT_LOGGER
      end

      AcidicJob::LogSubscriber.attach_to :acidic_job
    end

    initializer "acidic_job.active_job.extensions" do
      ActiveSupport.on_load :active_job do
        require "active_job/serializers"
        require_relative "serializers/exception_serializer"
        require_relative "serializers/new_record_serializer"
        require_relative "serializers/job_serializer"
        require_relative "serializers/range_serializer"

        ActiveJob::Serializers.add_serializers(
          Serializers::ExceptionSerializer,
          Serializers::NewRecordSerializer,
          Serializers::JobSerializer,
          Serializers::RangeSerializer,
        )
      end
    end

    # :nocov:
    generators do
      require "generators/acidic_job/install_generator"
    end
    # :nocov:
  end
end
