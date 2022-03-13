# frozen_string_literal: true

module AcidicJob
  module Extensions
    module Noticed
      extend ActiveSupport::Concern

      class_methods do
        def deliver_acidicly(recipients, idempotency_key: nil, unique_by: nil)
          new.deliver_acidicly(recipients, idempotency_key: idempotency_key, unique_by: unique_by)
        end
      end

      def deliver_acidicly(recipients, idempotency_key: nil, unique_by: nil)
        # THIS IS A HACK THAT COPIES AND PASTES KEY PARTS OF THE `Noticed::Base` CODE
        # IN ORDER TO ALLOW US TO TRANSACTIONALLY DELIVER NOTIFICATIONS
        # THIS IS THUS LIABLE TO BREAK WHENEVER THAT GEM IS UPDATED
        delivery_methods = self.class.delivery_methods.dup

        Array.wrap(recipients).uniq.each do |recipient|
          if (index = delivery_methods.find_index { |m| m[:name] == :database })
            database_delivery_method = delivery_methods.delete_at(index)
            self.record = run_delivery_method(database_delivery_method,
                                              recipient: recipient,
                                              enqueue: false,
                                              record: nil)
          end

          delivery_methods.map do |delivery_method|
            job_class = delivery_method_for(delivery_method[:name], delivery_method[:options])
            args = {
              notification_class: self.class.name,
              options: delivery_method[:options],
              params: params,
              recipient: recipient,
              record: record
            }
            serialized_job = job_class.send(:job_or_instantiate, args).serialize
            acidic_identifier = job_class.respond_to?(:acidic_identifier) ? job_class.acidic_identifier : :job_id
            # generate `idempotency_key` either using [1] provided key, [2] provided uniqueness constraint, or [3] computed key
            key = if idempotency_key
              idempotency_key
            elsif unique_by
              IdempotencyKey.generate(unique_by: unique_by, job_class: job_class.name)
            else
              IdempotencyKey.new(acidic_identifier).value_for(serialized_job)
            end

            AcidicJob::Run.create!(
              staged: true,
              job_class: job_class.name,
              serialized_job: serialized_job,
              idempotency_key: key
            )
          end
        end
      end
      alias deliver_transactionally deliver_acidicly
    end
  end
end
