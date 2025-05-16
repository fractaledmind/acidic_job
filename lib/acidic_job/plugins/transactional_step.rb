# frozen_string_literal: true

module AcidicJob
  module Plugins
    module TransactionalStep
      extend self

      def keyword
        :transactional
      end

      # transactional: true
      # transactional: false
      # transactional: { on: Model }
      def validate(input)
        return input if input in true | false

        raise ArgumentError.new("argument must be boolean or hash") unless input in Hash
        raise ArgumentError.new("argument hash must have `on` key") unless input in Hash[on:]
        raise ArgumentError.new("`on` key must have module value") unless input in Hash[on: Module]

        input
      end

      def around_step(context, &block)
        return yield if context.definition == false

        model = if context.definition == true
                  AcidicJob::Execution
                else
                  context.definition["on"].constantize
                end

        model.transaction(&block)
      end
    end
  end
end
