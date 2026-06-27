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
          job_ids = context.get(:job_ids)[0]

          if job_ids.nil?
            # First entry: resolve the jobs to await, record everything needed to
            # track and (if necessary) re-drive them, then enqueue and halt.
            awaits_method_name = context.definition

            awaits_method = context.resolve_method(awaits_method_name)
            raise InvalidMethodError.new unless awaits_method.arity.zero?

            awaited_jobs = awaits_method.call

            unless awaited_jobs.is_a?(Array) && awaited_jobs.all? { |j| j.is_a?(ActiveJob::Base) }
              raise InvalidReturnValueError.new(awaited_jobs)
            end

            # Nothing to await — proceed immediately rather than halting forever
            # (no child would ever re-enqueue this workflow).
            return yield if awaited_jobs.empty?

            job_ids = awaited_jobs.map(&:job_id)
            plugin_names = context.plugins.map { |p| p.name }

            # Store each awaited job's completion record — including its
            # serialization so an interrupted enqueue can be re-driven — BEFORE
            # publishing the `job_ids` list. A crash before `job_ids` is stored
            # simply re-runs this branch; a crash after it is recovered by the
            # `else` branch, which re-enqueues anything not yet completed.
            awaited_jobs.each do |job|
              context.set(job.job_id => {
                "execution_id" => context.execution_id,
                "job_ids" => job_ids,
                "plugins" => plugin_names,
                "serialized" => job.serialize,
                "completed" => false
              })
            end
            context.set(job_ids: job_ids)

            context.record!(
              step: context.current_step,
              action: :awaiting,
              timestamp: Time.current,
              awaited_job_ids: job_ids
            )

            ActiveJob.perform_all_later(*awaited_jobs)

            context.halt_workflow!
          else
            # Resuming. Only run the step body once EVERY awaited job has reported
            # completion. The parent can land here not just when all children are
            # done, but also if Active Job retried it after a crash — so we must
            # verify, not assume.
            incomplete = job_ids.reject do |job_id|
              record = context.get(job_id)[0]
              record && record["completed"]
            end

            if incomplete.empty?
              yield
            else
              # Some awaited jobs never completed (e.g. a crash interrupted the
              # original enqueue, or a child has not finished yet). Re-enqueue the
              # missing ones from their stored serialization and wait again,
              # rather than running the body without its dependencies.
              incomplete.each do |job_id|
                record = context.get(job_id)[0]
                next unless record && record["serialized"]

                ActiveJob::Base.deserialize(record["serialized"]).enqueue
              end

              context.halt_workflow!
            end
          end
        end

        def after_perform(job)
          # Check if this job was awaited by a parent workflow
          # The awaits plugin stores: { job_id => { execution_id: X, job_ids: [...] } }
          awaited_record = AcidicJob::Value.find_by(key: job.job_id)

          return unless awaited_record
          return unless awaited_record.value.is_a?(Hash) && awaited_record.value.key?("execution_id")

          # Mark this job as completed
          awaited_record.update!(value: { **awaited_record.value, "completed" => true })

          # Get the parent execution and all sibling job IDs
          parent_execution_id = awaited_record.value["execution_id"]
          sibling_job_ids = awaited_record.value["job_ids"]

          return unless parent_execution_id && sibling_job_ids

          # Check if all sibling jobs are complete. Guard on the count too: an
          # empty/partial result set would make `all?` vacuously true and
          # re-enqueue the parent prematurely.
          sibling_records = AcidicJob::Value.where(execution_id: parent_execution_id, key: sibling_job_ids)
          all_complete = sibling_records.count == sibling_job_ids.size &&
                         sibling_records.all? { |record| record.value["completed"] == true }

          return unless all_complete

          # All awaited jobs are complete, re-enqueue the parent job
          parent_execution = AcidicJob::Execution.find(parent_execution_id)
          parent_execution.enqueue_job
        end
      end
    end
  end
end
