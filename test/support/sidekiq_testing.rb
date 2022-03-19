# frozen_string_literal: true

require "sidekiq/testing"

# inject retry logic into the testing harness
module Sidekiq
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
