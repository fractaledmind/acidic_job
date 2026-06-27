# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      # Retry gives a single step its own retry policy, independent of the job's
      # global `retry_on`. When the step raises a matching error, the step is
      # re-enqueued (with backoff) and re-run from scratch, up to `attempts`
      # times; once the budget is exhausted the error propagates normally (to the
      # job's `retry_on`/`discard_on` handling).
      #
      #   w.step :charge, retry: { on: Net::OpenTimeout, attempts: 5, backoff: :exponential }
      #   w.step :sync,   retry: { attempts: 3, backoff: 2 } # any error, fixed 2s
      module Retry
        extend self

        class InvalidOptionsError < AcidicJob::Error
          def message
            "retry: must be a Hash with an Integer `attempts:` (optional `on:` and `backoff:`)"
          end
        end

        def keyword
          :retry
        end

        # retry: { attempts: 3 }
        # retry: { on: Error, attempts: 5, backoff: :exponential }
        # retry: { on: [E1, E2], attempts: 3, backoff: 2 }
        def validate(input)
          raise InvalidOptionsError unless input in Hash
          raise InvalidOptionsError unless input in Hash[attempts: Integer]
          raise InvalidOptionsError unless input[:attempts] >= 1

          output = { "attempts" => input[:attempts] }

          if input.key?(:on)
            unless input[:on] in Module | Array[ Module ]
              raise ArgumentError.new("retry: `on` must be an error class or array of error classes")
            end
            output["on"] = Array(input[:on])
          end

          backoff = input.fetch(:backoff, :exponential)
          unless backoff in Numeric | :exponential | :linear
            raise ArgumentError.new("retry: `backoff` must be :exponential, :linear, or a number of seconds")
          end
          output["backoff"] = backoff.is_a?(Symbol) ? backoff.to_s : backoff

          output
        end

        def around_step(context) # &block
          yield
        rescue => e
          options = context.definition
          triggers = options["on"]

          # Only this plugin's configured error(s) are retried; anything else
          # propagates untouched (bare `raise` preserves the backtrace).
          raise if triggers && triggers.none? { |klass| klass === e }

          attempts = options["attempts"]
          prior_retries = context.entries_for_action(:retrying).for_step(context.current_step).count

          # Budget exhausted — let the error propagate to the job's own handling.
          raise if prior_retries >= attempts - 1

          wait = backoff_for(options["backoff"], prior_retries)

          context.record!(
            step: context.current_step,
            action: :retrying,
            timestamp: Time.current,
            attempt: prior_retries + 1,
            wait: wait,
            exception_class: e.class.name,
            message: e.message
          )

          # Re-enqueue this run with backoff; on the next pass the step re-runs
          # from scratch (it has no `succeeded` entry yet).
          context.enqueue_job(wait_until: Time.current + wait)
          context.halt_workflow!
        end

        private def backoff_for(strategy, prior_retries)
          case strategy
          when "exponential" then 2**prior_retries # 1, 2, 4, 8, ...
          when "linear"      then prior_retries + 1 # 1, 2, 3, ...
          else strategy                             # fixed number of seconds
          end
        end
      end
    end
  end
end
