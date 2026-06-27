# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module ForEach
        extend self

        # Sentinel marking an exhausted enumerator. Using a dedicated object
        # (rather than `nil`) lets a collection legitimately contain `nil`
        # elements without being mistaken for the end of iteration.
        DONE = Object.new.freeze
        private_constant :DONE

        class InvalidMethodError < AcidicJob::Error
          def message
            "for_each: must be a 0-arity method or require the `cursor` keyword argument"
          end
        end

        class UndefinedMethodError < AcidicJob::Error
          def initialize(method)
            @method = method
          end

          def message
            "for_each: undefined method: #{@method.inspect}"
          end
        end

        class InvalidReturnValueError < AcidicJob::Error
          def initialize(iterable)
            @iterable = iterable
          end

          def message
            "for_each: must return an Enumerable or Enumerator, was: #{@iterable.class}"
          end
        end

        def keyword
          :for_each
        end

        def validate(input)
          unless input in Enumerable | Symbol | String
            raise ArgumentError.new("value must be an enumerable or method name")
          end

          input
        end

        def around_step(context) # &block
          iterable = context.definition
          key = "#{keyword}/#{context.current_step}/cursor"
          cursor_position = context.get(key)[0] || -1
          enumerator = resolve_enumerator(context, iterable, cursor_position)
          result = resolve_item_and_cursor(enumerator)

          return if result == DONE

          item_from_enumerator, cursor_from_enumerator = result

          yield(item_from_enumerator)

          context.set(key => cursor_from_enumerator)
          context.record!(
            step: context.current_step,
            action: :iterated,
            timestamp: Time.current,
            cursor: cursor_from_enumerator
          )
          context.repeat_step!
        end

        private def resolve_enumerator(context, iterable, cursor_position)
          case iterable
          when Enumerable
            enumerable_to_enumerator(iterable, cursor_position)
          when Symbol, String
            if (iterable_method = context.resolve_method(iterable))
              if iterable_method.arity.zero?
                iterable_result = iterable_method.call
                ensure_enumerator(iterable_result, cursor_position)
              elsif iterable_method.arity == 1 && iterable_method.parameters.first == [ :keyreq, :cursor ]
                iterable_result = iterable_method.call(cursor: cursor_position)
                ensure_enumerator(iterable_result, cursor_position)
              else
                raise InvalidMethodError.new
              end
            else
              raise UndefinedMethodError.new(iterable)
            end
          else
            raise ArgumentError.new("for_each: must be an Enumerable, Symbol, or String")
          end
        end

        private def resolve_item_and_cursor(enumerator)
          enumerator.next
        rescue StopIteration
          DONE
        end

        private def enumerable_to_enumerator(enumerable, cursor_position)
          drop = cursor_position + 1
          enumerable.each_with_index.drop(drop).to_enum { enumerable.size - drop }
        end

        private def ensure_enumerator(iterable, cursor_position)
          case iterable
          when Enumerable
            enumerable_to_enumerator(iterable, cursor_position)
          when Enumerator
            iterable
          else
            raise InvalidReturnValueError.new(iterable)
          end
        end
      end
    end
  end
end
