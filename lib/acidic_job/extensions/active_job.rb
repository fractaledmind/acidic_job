# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module Extensions
    module ActiveJob
      extend ActiveSupport::Concern

      concerning :Serialization do
        class_methods do
          def serialize_with_arguments(*args, **kwargs)
            job_or_instantiate(*args, **kwargs).serialize
          end
        end

        def serialize_job(*_args, **_kwargs)
          serialize
        end
      end

      class_methods do
        def perform_acidicly(*args, **kwargs)
          raise UnsupportedExtension unless defined?(::ActiveJob) && self < ::ActiveJob::Base

          serialized_job = serialize_with_arguments(*args, **kwargs)
          key = IdempotencyKey.new(acidic_identifier).value_for(serialized_job)

          AcidicJob::Run.create!(
            staged: true,
            job_class: name,
            serialized_job: serialized_job,
            idempotency_key: key
          )
        end
        alias_method :perform_transactionally, :perform_acidicly
      end
    end
  end
end
