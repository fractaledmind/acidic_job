# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module Delay
        extend self

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
            wait_until = Time.current + wait

            # Enqueue the future job BEFORE recording the wait. If a crash
            # interrupts this pass, the `waiting` entry won't exist yet, so the
            # retry re-runs this branch and the future job is guaranteed to be
            # (re-)enqueued. The worst case is a duplicate future job, which is
            # harmless: whichever runs first completes the step; the other is a
            # no-op against the already-succeeded step.
            context.enqueue_job(wait_until: wait_until)
            context.record!(
              step: context.current_step,
              action: :waiting,
              timestamp: Time.current,
              wait_until: wait_until,
              duration: wait
            )
            context.halt_workflow!
          else
            waiting_entry = context.entries_for_action(:waiting).most_recent
            wait_until = waiting_entry.data[:wait_until]

            if Time.current >= wait_until
              yield
            else
              # :nocov:
              # Woke up before the deadline (clock skew, a backend that ran the
              # scheduled job early, or a manual enqueue). The run we are in may
              # be the only one scheduled, so re-enqueue for the deadline before
              # halting to guarantee the workflow resumes (a duplicate future run
              # is harmless — whichever runs at/after the deadline completes the
              # step, the rest are no-ops). Not exercised by the coverage job,
              # whose performer ignores scheduled-at times.
              context.enqueue_job(wait_until: wait_until)
              context.halt_workflow!
              # :nocov:
            end
          end
        end
      end
    end
  end
end
