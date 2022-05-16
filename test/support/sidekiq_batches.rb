# frozen_string_literal: true

require_relative "sidekiq_testing"

module Support
  module Sidekiq
    class NullObject
      # :nocov:
      def method_missing(*_args)
        self
      end

      def respond_to_missing?(*_args)
        true
      end
      # :nocov:
    end

    class NullBatch < NullObject
      attr_accessor :description
      attr_reader :bid

      @@batches = [] # rubocop:disable Style/ClassVars

      def initialize(bid = nil)
        super()
        @bid = bid || SecureRandom.hex(8)
        @callbacks = []
      end

      def status
        NullStatus.new(@bid, @callbacks)
      end

      def on(*args)
        @callbacks << args
        @@batches << self
      end

      def jobs(*)
        yield
      end
    end

    class NullStatus < NullObject
      attr_reader :bid

      def initialize(bid, callbacks = [])
        super()
        @bid = bid
        @callbacks = callbacks
      end

      # :nocov:
      def failures
        0
      end

      def join
        ::Sidekiq::Worker.drain_all

        @callbacks.each do |event, callback, options|
          next unless event != :success || failures.zero?

          case callback
          when Class
            callback.new.send("on_#{event}", self, options)
          when String
            klass, meth = callback.split("#")
            klass.constantize.new.send(meth, self, options)
          else
            raise ArgumentError, "Unsupported callback notation"
          end
        end
      end

      def total
        ::Sidekiq::Worker.jobs.size
      end
      # :nocov:
    end

    class Workflow; end # rubocop:disable Lint/EmptyClass

    class StepWorker
      include ::Sidekiq::Worker
      include ::AcidicJob

      def self.inherited(subclass)
        super
        subclass.set_callback :perform, :after, :call_batch_success_callback
        subclass.set_callback :finish, :after, :call_batch_success_callback
      end

      def call_batch_success_callback
        return if acidic_job_run.present? && !acidic_job_run.finished?

        # simulate the Sidekiq::Batch success callback
        success_callback = batch.instance_variable_get(:@callbacks).find { |on, *| on == :success }
        _, method_sig, options = success_callback
        class_name, method_name = method_sig.split("#")
        class_name.constantize.new.send(method_name, batch.status, options)
      end

      def batch
        ObjectSpace.each_object(Support::Sidekiq::NullBatch).find do |null_batch|
          success_callback = null_batch.instance_variable_get(:@callbacks).find { |on, *| on == :success }
          _event, receiver, options = success_callback

          receiver.is_a?(String) && receiver.end_with?("#step_done") && options["job_names"].include?(self.class.name)
        end
      end
    end
  end
end

module Sidekiq
  class Batch < Support::Sidekiq::NullBatch
    class Status < Support::Sidekiq::NullStatus; end
  end
end
