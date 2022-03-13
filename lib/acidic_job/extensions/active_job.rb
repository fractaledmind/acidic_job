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
          # use either [1] provided uniqueness constraint or [2] computed key
          key = if kwargs.key?(:unique_by) || kwargs.key?("unique_by")
                  unique_by = [kwargs[:unique_by], kwargs["unique_by"]].compact.first
                  IdempotencyKey.generate(unique_by: unique_by, job_class: name)
                else
                  IdempotencyKey.new(acidic_identifier).value_for(serialized_job)
                end

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
