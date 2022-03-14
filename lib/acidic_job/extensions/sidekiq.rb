# frozen_string_literal: true

require "active_support/concern"
require "active_support/callbacks"
require "active_support/core_ext/module/concerning"

module AcidicJob
  module Extensions
    module Sidekiq
      extend ActiveSupport::Concern

      concerning :Serialization do
        class_methods do
          # called only from `AcidicJob::Run#enqueue_staged_job`
          def deserialize(serialized_job_hash)
            klass = serialized_job_hash["class"].constantize
            worker = klass.new
            worker.jid = serialized_job_hash["jid"]
            worker.instance_variable_set(:@args, serialized_job_hash["args"])

            worker
          end

          # called only from `AcidicJob::PerformAcidicly#perform_acidicly`
          # and `AcidicJob::DeliverAcidicly#deliver_acidicly`
          def serialize_with_arguments(args = [], _kwargs = nil)
            # THIS IS A HACK THAT ESSENTIALLY COPIES THE CODE FROM THE SIDEKIQ CODEBASE TO MIMIC THE BEHAVIOR
            args = Array[args]
            normalized_args = ::Sidekiq.load_json(::Sidekiq.dump_json(args))
            item = { "class" => self, "args" => normalized_args }
            dummy_sidekiq_client = ::Sidekiq::Client.new
            normed = dummy_sidekiq_client.send :normalize_item, item
            dummy_sidekiq_client.send :process_single, item["class"], normed
          end
        end

        def serialize_job(*args, **kwargs)
          # `@args` is only set via `deserialize`; it is not a standard Sidekiq thing
          arguments = args || @args
          arguments += [kwargs] unless kwargs.empty?
          normalized_args = ::Sidekiq.load_json(::Sidekiq.dump_json(arguments))
          item = { "class" => self.class, "args" => normalized_args, "jid" => jid }
          sidekiq_options = sidekiq_options_hash || {}

          sidekiq_options.merge(item)
        end

        # called only from `AcidicJob::Run#enqueue_staged_job`
        def enqueue
          ::Sidekiq::Client.push(
            "class" => self.class,
            "args" => @args,
            "jid" => @jid
          )
        end
      end

      concerning :PerformAcidicly do
        class_methods do
          def perform_acidicly(*args, **kwargs)
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

      # to balance `perform_async` class method
      concerning :PerformSync do
        class_methods do
          def perform_sync(*args, **kwargs)
            new.perform(*args, **kwargs)
          end
        end
      end

      # Following approach used by ActiveJob
      # https://github.com/rails/rails/blob/93c9534c9871d4adad4bc33b5edc355672b59c61/activejob/lib/active_job/callbacks.rb
      concerning :Callbacks do
        class_methods do
          def around_perform(*filters, &blk)
            set_callback(:perform, :around, *filters, &blk)
          end

          def before_perform(*filters, &blk)
            set_callback(:perform, :before, *filters, &blk)
          end

          def after_perform(*filters, &blk)
            set_callback(:perform, :after, *filters, &blk)
          end
        end
      end
    end
  end
end
