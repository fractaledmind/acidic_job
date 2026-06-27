# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module Compensate
        extend self

        class InvalidMethodError < AcidicJob::Error
          def message
            "compensate: must be a 0-arity method"
          end
        end

        class UndefinedMethodError < AcidicJob::Error
          def initialize(method)
            @method = method
          end

          def message
            "compensate: undefined method: #{@method.inspect}"
          end
        end

        def keyword
          :compensate
        end

        def validate(input)
          raise ArgumentError.new("argument must be hash") unless input in Hash

          output = {}

          case input
          in Hash[on: error, with: method]
            unless error in Module | Array[Module]
              raise ArgumentError.new("compensate: `on` value must be error class or array of errors")
            end
            unless method in Symbol | String
              raise ArgumentError.new("compensate: `with` value must be method name")
            end

            output["on"] = Array(input[:on])
            output["with"] = input[:with].to_s
          in Hash[with: method]
            unless method in Symbol | String
              raise ArgumentError.new("compensate: `with` value must be method name")
            end

            output["with"] = input[:with].to_s
          else
            raise ArgumentError.new("compensate: `with` key must be present")
          end

          output
        end

        def around_step(context) # &block
          yield
        rescue => e
          compensate = context.definition
          triggers = compensate["on"]
          compensation = compensate["with"]

          # Only compensate for the configured error(s). Any other error must
          # propagate untouched — never swallow an unexpected failure.
          raise e if triggers&.none? { |klass| klass === e }

          method = context.resolve_method(compensation)
          raise InvalidMethodError.new(compensation) unless method.arity.zero?

          context.record!(
            step: context.current_step,
            action: :compensating,
            timestamp: Time.current
          )
          method.call

          # Compensation is cleanup, not recovery: the original failure still
          # stands, so re-raise it for normal retry/discard handling.
          raise e
        end
      end
    end
  end
end
