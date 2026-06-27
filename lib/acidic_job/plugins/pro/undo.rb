# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      # Undo turns a workflow into a saga: each step can register a compensating
      # method, and if the workflow ultimately *fails* (the job is discarded
      # after exhausting its retries, or via `discard_on`), the compensations of
      # every already-completed step are run in REVERSE order to unwind the work.
      #
      #   discard_on Stripe::CardError
      #
      #   w.step :reserve_inventory, undo: :release_inventory
      #   w.step :charge_payment,    undo: :refund_payment
      #   w.step :ship
      #
      # If `ship` fails terminally, `refund_payment` then `release_inventory`
      # run (reverse order). Compensations execute on the job instance, so they
      # can read whatever the forward steps stored in `ctx`.
      #
      # Unlike `compensate:` (which cleans up a SINGLE step's own failure and
      # re-raises), `undo:` rolls back EARLIER, already-succeeded steps when a
      # LATER step brings the whole workflow down.
      module Undo
        extend self

        class InvalidMethodError < AcidicJob::Error
          def message
            "undo: must be a 0-arity method"
          end
        end

        def keyword
          :undo
        end

        def validate(input)
          raise ArgumentError.new("undo: value must be a method name") unless input in Symbol | String

          input.to_s
        end

        # During normal execution the step just runs; `undo:` only matters on
        # terminal failure. We resolve the method here purely to fail fast on a
        # misconfigured name/arity rather than discovering it only at rollback.
        def around_step(context)
          method = context.resolve_method(context.definition)
          raise InvalidMethodError unless method.arity.zero?

          yield
        end

        # Run on terminal failure (via the workflow's `after_discard` hook).
        # Walk the succeeded steps in reverse and invoke each one's registered
        # compensation, recording an entry so a given step is only undone once.
        def after_discard(job, execution)
          succeeded_steps = execution.entries.for_action("succeeded").ordered.pluck(:step)

          succeeded_steps.reverse_each do |step|
            undo_method = execution.definition_for(step)["undo"]
            next unless undo_method
            next if execution.entries.for_step(step).for_action(plugin_action(:undone)).exists?

            begin
              job.send(undo_method)
              execution.record!(step: step, action: plugin_action(:undone), timestamp: Time.current)
            rescue => e
              # A compensation failed. Record it for visibility and keep
              # unwinding the remaining steps — one failed rollback must not
              # strand the others. Compensations should be reliable + idempotent.
              execution.record!(
                step: step,
                action: plugin_action(:failed),
                timestamp: Time.current,
                exception_class: e.class.name,
                message: e.message
              )
            end
          end
        end

        private def plugin_action(action)
          "#{keyword}/#{action}"
        end
      end
    end
  end
end
