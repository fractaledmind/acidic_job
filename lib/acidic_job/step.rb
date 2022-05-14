# frozen_string_literal: true

module AcidicJob
  # Each AcidicJob::Step requires two phases: [1] execution and [2] progression
  class Step
    def initialize(step, run, job, step_result = nil)
      @step = step
      @run = run
      @job = job
      @step_result = step_result
    end

    # The execution phase performs the work of the defined step
    def execute
      rescued_error = false
      step_callable = wrap_step_as_acidic_callable @step

      begin
        @run.with_lock do
          @step_result = step_callable.call(@run)
        end
      # QUESTION: Can an error not inherit from StandardError
      rescue StandardError => e
        rescued_error = e
        raise e
      ensure
        if rescued_error
          # If we're leaving under an error condition, try to unlock the job
          # run right away so that another request can try again.
          begin
            @run.update_columns(locked_at: nil, error_object: rescued_error)
          rescue StandardError => e
            # We're already inside an error condition, so swallow any additional
            # errors from here and just send them to logs.
            # TODO: implement and use a logger here
            puts "Failed to unlock AcidicJob::Run #{@run.id} because of #{e}."
          end
        end
      end
    end

    # The progression phase advances the job run state machine onto the next step
    def progress
      @run.with_lock do
        @step_result.call(run: @run)
      end
    end

    private

    def wrap_step_as_acidic_callable(step)
      # {"does" => :enqueue_step, "then" => :next_step, "awaits" => [WorkerWithEnqueueStep::FirstWorker]}
      current_step = step["does"]
      next_step = step["then"]
      # to support iteration within steps
      iterable_key = step["for_each"]
      iterated_key = "processed_#{iterable_key}"
      iterables = @run.attr_accessors.fetch(iterable_key, [])
      iterateds = @run.attr_accessors.fetch(iterated_key, [])
      next_item = iterables.reject { |item| iterateds.include? item }.first

      # jobs can have no-op steps, especially so that they can use only the async/await mechanism for that step
      callable = if @job.respond_to?(current_step, _include_private = true)
                   @job.method(current_step)
                 else
                   proc {}
                 end

      # return a callable Proc with a consistent interface for the execution phase
      proc do |run|
        result = if iterable_key.present? && next_item.present?
                   callable.call(next_item)
                 elsif iterable_key.present? && next_item.nil?
                   true
                 elsif callable.arity.zero?
                   callable.call
                 elsif callable.arity == 1
                   callable.call(run)
                 else
                   raise TooManyParametersForStepMethod
                 end

        if result.is_a?(FinishedPoint)
          result
        elsif next_item.present?
          iterateds << next_item
          @run.attr_accessors[iterated_key] = iterateds
          @run.save!(validate: false)
          RecoveryPoint.new(current_step)
        elsif next_step.to_s == Run::FINISHED_RECOVERY_POINT
          FinishedPoint.new
        else
          RecoveryPoint.new(next_step)
        end
      end
    end
  end
end
