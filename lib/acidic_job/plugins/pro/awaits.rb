# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module Awaits
        extend self

        class InvalidMethodError < AcidicJob::Error
          def message
            "awaits: must be a 0-arity method that returns an array of jobs"
          end
        end

        class UndefinedMethodError < AcidicJob::Error
          def initialize(method)
            @method = method
          end

          def message
            "awaits: undefined method: #{@method.inspect}"
          end
        end

        class InvalidReturnValueError < AcidicJob::Error
          def initialize(value)
            @value = value
          end

          def message
            "awaits: method must return an Array of ActiveJob::Base instances, got: #{@value.class}"
          end
        end

        def keyword
          :awaits
        end

        def validate(input)
          unless input in Symbol | String
            raise ArgumentError.new("value must be a method name (Symbol or String)")
          end

          input.to_s
        end

        def around_step(context) # &block
          if context.entries_for_action(:awaiting).empty?
            # First time: resolve the jobs from the method and enqueue them
            awaits_method_name = context.definition

            if (awaits_method = context.resolve_method(awaits_method_name))
              raise InvalidMethodError.new unless awaits_method.arity.zero?

              awaited_jobs = awaits_method.call

              unless awaited_jobs.is_a?(Array) && awaited_jobs.all? { |j| j.is_a?(ActiveJob::Base) }
                raise InvalidReturnValueError.new(awaited_jobs)
              end
            else
              raise UndefinedMethodError.new(awaits_method_name)
            end

            job_ids = awaited_jobs.map(&:job_id)

            context.record!(
              step: context.current_step,
              action: :awaiting,
              timestamp: Time.current,
              awaited_job_ids: job_ids
            )

            # Store the list of all job IDs for later reference
            context.set(job_ids: job_ids)

            # Store each awaited job with the info needed for the after_perform callback
            # to know which parent execution to re-enqueue when all jobs complete
            awaited_jobs.each do |job|
              context.set(job.job_id => {
                "execution_id" => context.execution_id,
                "job_ids" => job_ids,
                "completed" => false
              })
            end

            ActiveJob.perform_all_later(*awaited_jobs)

            context.halt_workflow!
          else
            yield
          end
        end
      end
    end
  end
end
