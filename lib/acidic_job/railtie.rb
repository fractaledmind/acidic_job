# frozen_string_literal: true

require "rails/railtie"

module AcidicJob
  class Railtie < ::Rails::Railtie
    initializer "acidic_job.action_mailer_extension" do
      ::ActiveSupport.on_load(:action_mailer) do
        # Add `deliver_acidicly` to ActionMailer
        ::ActionMailer::Parameterized::MessageDelivery.include(Extensions::ActionMailer)
        ::ActionMailer::MessageDelivery.include(Extensions::ActionMailer)
      end
    end

    initializer "acidic_job.active_job_serializers" do
      ::ActiveSupport.on_load(:active_job) do
        ::ActiveJob::Serializers.add_serializers(
          Serializers::ExceptionSerializer,
          Serializers::FinishedPointSerializer,
          Serializers::JobSerializer,
          Serializers::RangeSerializer,
          Serializers::RecoveryPointSerializer,
          Serializers::WorkerSerializer,
          Serializers::ActiveKiqSerializer
        )
      end
    end

    # :nocov:
    generators do
      require "generators/acidic_job/install_generator"
    end
    # :nocov:

    # This hook happens after all initializers are run, just before returning
    config.after_initialize do
      if defined?(::Noticed)
        # Add `deliver_acidicly` to Noticed
        ::Noticed::Base.include(Extensions::Noticed)
      end
    end
  end
end
