# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module Compensate
        extend self

        class InvalidMethodError < AcidicJob::Error
          def message
            "skip_if: must be a 0-arity method"
          end
        end

        class UndefinedMethodError < AcidicJob::Error
          def initialize(method)
            @method = method
          end

          def message
            "skip_if: undefined method: #{@method.inspect}"
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

          return if triggers&.none? { |klass| klass === e }

          if (method = context.resolve_method(compensation))
            raise InvalidMethodError.new(compensation) unless method.arity.zero?

            context.record!(
              step: context.current_step,
              action: :compensating,
              timestamp: Time.current
            )
            method.call
          else
            raise UndefinedMethodError.new(skip_if)
          end
        end
      end
    end
  end
end
