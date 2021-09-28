# frozen_string_literal: true

module AcidicJob
  module PerformWrapper
    def perform(*args, **kwargs)
      @arguments_for_perform = if args.any? && kwargs.any?
        args + [kwargs]
      elsif args.any? && kwargs.none?
        args
      elsif args.none? && kwargs.any?
        [kwargs]
      else
        []
      end
      super
    end
  end
end
