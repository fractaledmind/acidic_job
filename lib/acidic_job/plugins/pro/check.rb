# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module Check
        extend self

        class InvalidMethodError < AcidicJob::Error
          def message
            "check: must be a 0-arity method"
          end
        end

        class UndefinedMethodError < AcidicJob::Error
          def initialize(method)
            @method = method
          end

          def message
            "check: undefined method: #{@method.inspect}"
          end
        end

        def keyword
          :check
        end

        def validate(input)
          raise ArgumentError.new("argument must be hash") unless input in Hash

          output = {}

          case input
          in Hash[every: duration, until: check]
            unless duration in Numeric | ActiveSupport::Duration
              raise ArgumentError.new("`every` key must have duration value")
            end
            unless check in Symbol | String
              raise ArgumentError.new("`until` key must have method name")
            end

            output["every"] = input[:every].to_i
            output["until"] = input[:until].to_s
          in Hash[until: check]
            unless check in Symbol | String
              raise ArgumentError.new("`until` key must have method name")
            end

            output["until"] = input[:until].to_s
          else
            raise ArgumentError.new("`until` key must be present")
          end

          output
        end

        def around_step(context) # &block
          delay_check = context.definition["until"]

          if (check_method = context.resolve_method(delay_check))
            raise InvalidMethodError.new(delay_check) unless check_method.arity.zero?

            if check_method.call
              yield
            else
              wait = context.definition["every"]
              wait_until = Time.current + wait

              context.record!(
                step: context.current_step,
                action: :waiting,
                timestamp: Time.current,
                wait_until: wait_until,
                duration: wait
              )

              context.enqueue_job(wait_until: wait_until)
              context.halt_workflow!
            end
          else
            raise UndefinedMethodError.new(delay_check)
          end
        end
      end
    end
  end
end
