# frozen_string_literal: true

require "sidekiq"
require "sidekiq/testing"
require "sidekiq/job_retry"

Sidekiq::Testing.fake!

# inject retry logic into the testing harness
module Sidekiq
  class JobRetry
    def local(jobinst, jobstr, queue)
      yield
    rescue Handled, Sidekiq::Shutdown => e
      # ignore, will be pushed back onto queue during hard_shutdown
      raise e
    rescue StandardError => e
      p e

      # ignore, will be pushed back onto queue during hard_shutdown
      raise Sidekiq::Shutdown if exception_caused_by_shutdown?(e)

      msg = Sidekiq.load_json(jobstr)
      msg["retry"] = jobinst.class.get_sidekiq_options["retry"] if msg["retry"].nil?

      raise e unless msg["retry"]

      attempt_retry(jobinst, msg, queue, e)
      # We've handled this error associated with this job, don't
      # need to handle it at the global level
      raise Skip
    end
  end

  module Worker
    module ClassMethods
      def process_job(job)
        inst = new
        inst.jid = job["jid"]
        inst.bid = job["bid"] if inst.respond_to?(:bid=)

        dispatch(job, job["queue"], Sidekiq.dump_json(job)) do |instance|
          Sidekiq::Testing.server_middleware.invoke(instance, job, job["queue"]) do
            execute_job(instance, job["args"])
          end
        end
      end

      def dispatch(job_hash, queue, jobstr)
        @retrier ||= Sidekiq::JobRetry.new
        @retrier.global(jobstr, queue) do
          klass = constantize(job_hash["class"])
          inst = klass.new
          inst.jid = job_hash["jid"]
          @retrier.local(inst, jobstr, queue) do
            yield inst
          end
        end
      end

      def constantize(str)
        return Object.const_get(str) unless str.include?("::")

        names = str.split("::")
        names.shift if names.empty? || names.first.empty?

        names.inject(Object) do |constant, name|
          # the false flag limits search for name to under the constant namespace
          #   which mimics Rails' behaviour
          constant.const_get(name, false)
        end
      end
    end
  end
end
