# frozen_string_literal: true

module AcidicJob
  module Plugins
    module Pro
      module Awaits
        extend self

        def keyword
          :awaits
        end

        def validate(input)
          unless input in Array
            raise ArgumentError.new("value must be an array")
          end

          input
        end

        def around_step(context) # &block
          awaited_jobs = context.definition

          if context.entries_for_action(:awaiting).empty?
            context.record!(
              step: context.current_step,
              action: :awaiting,
              timestamp: Time.current,
              awaited_job_ids: awaited_jobs.map(&:job_id)
            )

            context.set(job_ids: awaited_jobs.map(&:job_id))
            awaited_jobs.each do |job|
              context.fetch(job.job_id) { job }
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
