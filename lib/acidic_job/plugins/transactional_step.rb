# frozen_string_literal: true

module AcidicJob
  module Plugins
    module TransactionalStep
      extend self

      def keyword
        :transactional
      end

      def validate(input)
        return true if input in true | false

        raise ArgumentError.new("argument must be boolean or hash") unless input in Hash
        raise ArgumentError.new("argument hash must have `on` key") unless input in Hash[on:]
        raise ArgumentError.new("`on` key must have module value") unless input in Hash[on: Module]

        input
      end

      def wrap(transactional:, **, &block)
        return yield if transactional == false

        on = transactional == true ? AcidicJob::Execution : transactional["on"].constantize

        on.transaction(&block)
      end
    end
  end
end
