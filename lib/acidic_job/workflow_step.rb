# frozen_string_literal: true

module AcidicJob
  class WorkflowStep
    def initialize(run:, job:)
      @run = run
      @job = job
    end

    def wrapped
      # return a callable Proc with a consistent interface for the execution phase
      proc do |_run|
        current_step_result = process_current_step

        if current_step_result.is_a?(FinishedPoint)
          current_step_result
        elsif next_item.present?
          @run.attr_accessors[iterated_key] = prev_iterateds + [next_item]
          @run.save!(validate: false)
          RecoveryPoint.new(current_step_name)
        elsif @run.next_step_finishes?
          FinishedPoint.new
        else
          RecoveryPoint.new(@run.next_step_name)
        end
      end
    end

    private

    def process_current_step
      result = nil

      if iterable_key.present? && next_item.present? # have an item to iterate over, so pass it to the step method
        result = current_callable.call(next_item)
      elsif iterable_key.present? && next_item.nil? # have iterated over all items
        result = true
      elsif current_callable.arity.zero?
        result = current_callable.call
      else
        raise TooManyParametersForStepMethod
      end

      result
    end

    def current_callable
      return @job.method(current_step_name) if @job.respond_to?(current_step_name, _include_private = true)
      # jobs can have no-op steps, especially so that they can use only the async/await mechanism for that step
      return proc {} if @run.current_step_hash["awaits"].present?

      raise UndefinedStepMethod
    end

    def iterable_key
      # the `iterable_key` represents the name of the collection accessor
      # that must be present in `@run.attr_accessors`; that is,
      # it must have been passed to `persisting` when calling `with_acidic_workflow`
      for_each = @run.current_step_hash["for_each"]

      return unless for_each.present?

      return for_each if @run.attr_accessors.key?(for_each)

      raise UnknownForEachCollection
    end

    def iterated_key
      # in order to ensure we don't iterate over successfully iterated values in previous runs,
      # we need to store the collection of already processed values.
      # we store this collection under a key bound to the current step to ensure multiple steps
      # can iterate over the same collection.
      "processed_#{current_step_name}_#{iterable_key}"
    end

    def prev_iterables
      # The collection of values to iterate over
      iterables = @run.attr_accessors.fetch(iterable_key, [])

      return Array(iterables) if iterables.is_a?(Enumerable)

      raise UniterableForEachCollection
    end

    def prev_iterateds
      # The collection of values already iterated over
      iterateds = @run.attr_accessors.fetch(iterated_key, [])

      Array(iterateds)
    end

    def next_item
      # The collection of values to iterate over now
      curr_iterables = prev_iterables - prev_iterateds

      curr_iterables.first
    end

    def current_step_name
      @run.current_step_name
    end
  end
end
