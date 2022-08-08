# frozen_string_literal: true

module AcidicJob
  module Extensions
    module Noticed
      extend ActiveSupport::Concern

      class_methods do
        def deliver_acidicly(recipients)
          new.deliver_acidicly(recipients)
        end
      end

      # THIS IS A HACK THAT COPIES AND PASTES KEY PARTS OF THE `Noticed::Base` CODE
      # IN ORDER TO ALLOW US TO TRANSACTIONALLY DELIVER NOTIFICATIONS
      # THIS IS THUS LIABLE TO BREAK WHENEVER THAT GEM IS UPDATED
      def deliver_acidicly(recipients)
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
            job = job_class.new(args)

            AcidicJob::Run.stage!(job)
          end
        end
      end
    end
  end
end
