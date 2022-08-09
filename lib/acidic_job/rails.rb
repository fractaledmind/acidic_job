# frozen_string_literal: true

require "rails/railtie"

module AcidicJob
  class Rails < ::Rails::Railtie
    initializer "acidic_job.action_mailer_extension" do
      ActiveSupport.on_load(:action_mailer) do
        # Add `deliver_acidicly` to ActionMailer
        if defined?(::ActionMailer)
          ::ActionMailer::Parameterized::MessageDelivery.include(::AcidicJob::Extensions::ActionMailer)
        end
        ::ActionMailer::MessageDelivery.include(::AcidicJob::Extensions::ActionMailer) if defined?(::ActionMailer)
      end
    end

    generators do
      require "generators/acidic_job/install_generator"
    end

    # This hook happens after all initializers are run, just before returning
    config.after_initialize do
      if defined?(::Noticed)
        # Add `deliver_acidicly` to Noticed
        ::Noticed::Base.include(Extensions::Noticed)
      end
    end
  end
end
