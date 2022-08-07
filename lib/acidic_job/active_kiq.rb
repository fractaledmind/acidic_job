# frozen_string_literal: true

require "sidekiq"
require "active_support/callbacks"
require "active_support/core_ext/module/concerning"
require_relative "mixin"

module AcidicJob
  class ActiveKiq
    include ::Sidekiq::Worker
    include ::Sidekiq::JobUtil
    include ::ActiveSupport::Callbacks
    define_callbacks :perform
    include Mixin

    concerning :Initializing do
      included do
        attr_accessor :arguments
        attr_accessor :job_id
        attr_accessor :queue_name
        attr_accessor :sidekiq_options
      end
      ##
      # Creates a new job instance.
      # +args+ are the arguments, if any, that will be passed to the perform method
      # +opts+ are any options to configure the job
      def initialize(*arguments)
        @arguments  = arguments
        @job_id     = SecureRandom.uuid
        @sidekiq_options = sidekiq_options_hash || Sidekiq.default_job_options
        @queue_name = @sidekiq_options["queue"]
      end

      # Sidekiq sets the `jid` when it is processing jobs off of the Redis queue.
      # We override the job identifier when staging jobs to encode the `Run` record global id.
      # We also override how "ActiveKiq" instance's expose the job identifier to match ActiveJob.
      # So, we need to ensure that when `jid=` is called, we set the `job_id` instead.
      def jid=(value)
        super
        @job_id = value
      end
    end

    concerning :Performing do
      class_methods do
        def perform_now(*args, **kwargs)
          new.perform(*args, **kwargs)
        end
      end

      def perform_now(*args, **kwargs)
        perform(*args, **kwargs)
      end

      def enqueue
        ::Sidekiq::Client.push(
          "class" => self.class,
          "args" => @arguments,
          "jid" => @job_id,
          "queue" => @queue_name
        )
      end
    end

    concerning :Serializing do
      class_methods do
        def deserialize(job_data)
          job = job_data["job_class"].constantize.new
          job.deserialize(job_data)
          job
        end
      end

      def serialize
        return @serialize if defined? @serialize

        item = @sidekiq_options.merge("class" => self.class.name, "args" => @arguments || [])
        worker_hash = normalize_item(item)

        @serialize = {
          "job_class" => worker_hash["class"],
          "job_id" => @job_id,
          "queue_name" => worker_hash["queue"],
          "arguments" => worker_hash["args"]
        }.merge(worker_hash.except("class", "jid", "queue", "args"))
      end

      def deserialize(job_data)
        self.job_id = job_data["job_id"]
        self.queue_name = job_data["queue_name"]
        self.arguments = job_data["arguments"]
        self
      end
    end

    # Following approach used by ActiveJob
    # https://github.com/rails/rails/blob/93c9534c9871d4adad4bc33b5edc355672b59c61/activejob/lib/active_job/callbacks.rb
    concerning :Callbacks do
      class_methods do
        def around_perform(*filters, &blk)
          set_callback(:perform, :around, *filters, &blk)
        end

        def before_perform(*filters, &blk)
          set_callback(:perform, :before, *filters, &blk)
        end

        def after_perform(*filters, &blk)
          set_callback(:perform, :after, *filters, &blk)
        end
      end
    end
  end
end
