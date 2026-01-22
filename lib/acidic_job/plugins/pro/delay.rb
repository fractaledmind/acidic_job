# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module Delay
        extend self

        class WaitingError < Error
          def initialize(now, wait_until, step)
            @now = now
            @wait_until = wait_until
            @step = step
          end

          def message
            "expected step #{@step.inspect} to be performed on or after #{@wait_until.inspect}, but was performed at #{@now.inspect}"
          end
        end

        def keyword
          :delay
        end

        def validate(input)
          unless input in ActiveSupport::Duration | Numeric
            raise ArgumentError.new("value must be a duration or number of seconds")
          end

          input.to_i
        end

        def around_step(context) # &block
          if context.entries_for_action(:waiting).empty?
            wait = context.definition
            wait_until = Time.now + wait

            context.record!(
              step: context.current_step,
              action: :waiting,
              timestamp: Time.current,
              wait_until: wait_until,
              duration: wait
            )

            context.enqueue_job(wait_until: wait_until)
            context.halt_workflow!
          else
            waiting_entry = context.entries_for_action(:waiting).most_recent
            wait_until = waiting_entry.data[:wait_until]
            now = Time.current

            if now >= wait_until
              yield
            else
              raise WaitingError.new(now, wait_until, context.current_step)
            end
          end
        end
      end
    end
  end
end
