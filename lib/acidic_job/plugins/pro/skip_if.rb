# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module SkipIf
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
          :skip_if
        end

        def validate(input)
          unless input in Symbol | String
            raise ArgumentError.new("value must be a method name")
          end

          input
        end

        def around_step(context) # &block
          skip_if = context.definition

          if (check_method = context.resolve_method(skip_if))
            raise InvalidMethodError.new(skip_if) unless check_method.arity.zero?

            if check_method.call
              context.record!(
                step: context.current_step,
                action: :skipping,
                timestamp: Time.current
              )
            else
              yield
            end
          else
            raise UndefinedMethodError.new(skip_if)
          end
        end
      end
    end
  end
end
