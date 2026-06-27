# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      # AwaitSignal pauses a step until an external signal arrives. The named
      # method is checked each time the step runs: if it returns truthy the step
      # proceeds; otherwise the workflow halts and waits. Unlike `check:` (which
      # re-schedules itself on a timer to poll), AwaitSignal does NOT reschedule
      # — it relies on an external event re-enqueuing the job to resume it.
      #
      #   w.step :await_approval, await_signal: :approved?
      #   w.step :activate
      #
      # The workflow resumes when something performs the job again with the SAME
      # `unique_by` (e.g. a webhook handler: `OnboardJob.perform_later(user_id)`).
      # This makes it the natural fit for human-in-the-loop gates and
      # event/webhook-driven workflows. (Because there is no self-reschedule, the
      # caller is responsible for re-triggering when the awaited event occurs.)
      module AwaitSignal
        extend self

        class InvalidMethodError < AcidicJob::Error
          def message
            "await_signal: must be a 0-arity method"
          end
        end

        def keyword
          :await_signal
        end

        def validate(input)
          raise ArgumentError.new("await_signal: value must be a method name") unless input in Symbol | String

          input.to_s
        end

        def around_step(context) # &block
          signal = context.definition
          signal_method = context.resolve_method(signal)
          raise InvalidMethodError unless signal_method.arity.zero?

          if signal_method.call
            yield
          else
            context.record!(step: context.current_step, action: :awaiting, timestamp: Time.current)
            context.halt_workflow!
          end
        end
      end
    end
  end
end
