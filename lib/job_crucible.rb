# frozen_string_literal: true

# If you have a job that needs to be resilient, put it through the crucible.

module JobCrucible
  class RetryableError < StandardError; end

  class Simulation
    def initialize(job, variations: 100, seed: nil, depth: 1)
      @template = job
      @variations = variations
      @seed = seed || Random.new_seed
      @random = Random.new(@seed)
      @depth = depth
    end

    def run(&callback)
      @template.class.retry_on RetryableError, attempts: @depth + 2

      debug "Running #{variants.size} simulations of the total #{permutations.size} possibilities..."

      scenarios.map do |scenario|
        run_scenario(scenario, &callback)
      end
    end

    def permutations
      callstack = capture_callstack
      error_locations = callstack.flat_map do |key, desc|
        [["before", key, desc], ["after", key, desc]]
      end
      error_locations.permutation(@depth)
    end

    def variants
      return permutations if @variations.nil?

      permutations.to_a.sample(@variations, random: @random)
    end

    def scenarios
      variants.map do |variant|
        scenario = Scenario.new
        variant.each_with_index do |(type, path_with_line, _desc), _i|
          scenario.public_send(type, path_with_line) { raise RetryableError }
        end
        scenario
      end
    end

    private

    def capture_callstack
      return @callstack if defined?(@callstack)

      @callstack = Set.new
      job_class = @template.class
      job_file_path = job_class.instance_method(:perform).source_location&.first

      trace = TracePoint.new(:line) do |tp|
        next if tp.defined_class == self.class
        next unless tp.path == job_file_path ||
                    tp.defined_class == job_class

        key = "#{tp.path}:#{tp.lineno}"
        desc = "#{tp.defined_class}##{tp.method_id}"

        @callstack << [key, desc]
      end

      trace.enable { @template.perform_now }

      @callstack
    end

    def run_scenario(scenario, &callback)
      debug "Running simulation with scenario: #{scenario}"

      events = []
      ActiveSupport::Notifications.subscribed(->(event) { events << event.dup }, /active_job/) do
        scenario.enable do
          job = clone_job_template_for(scenario)
          job.enqueue

          perform_all_enqueued_jobs
        end
      end

      scenario.events = events
      callback.call(scenario)
    end

    def clone_job_template_for(scenario)
      serialized_template = @template.serialize
      job = ActiveJob::Base.deserialize(serialized_template)
      job.job_id = scenario.to_s
      job.exception_executions = {}
      job
    end

    def perform_all_enqueued_jobs
      enqueued_jobs = @template.class.queue_adapter.enqueued_jobs
      performed_jobs = @template.class.queue_adapter.performed_jobs

      while enqueued_jobs.any?
        enqueued_jobs.each do |payload|
          enqueued_jobs.delete(payload)
          performed_jobs << payload
          instance = payload[:job].deserialize(payload)
          instance.scheduled_at = Time.at(payload[:at]) if payload.key?(:at)
          instance.perform_now
        end
      end
    end

    def debug(...)
      @template.logger.debug(...)
    end
  end

  class Scenario
    attr_reader :breakpoints
    attr_accessor :events

    def initialize
      @breakpoints = {}
    end

    def before(path_with_line, &block)
      set_breakpoint(path_with_line, :before, &block)
    end

    def after(path_with_line, &block)
      set_breakpoint(path_with_line, :after, &block)
    end

    def enable
      prev_key = nil
      trace = TracePoint.new(:line) do |tp|
        key = "#{tp.path}:#{tp.lineno}"

        begin
          if prev_key && @breakpoints.key?(prev_key)
            execute_block(@breakpoints[prev_key][:after])
          end

          if @breakpoints.key?(key)
            execute_block(@breakpoints[key][:before])
          end
        ensure
          prev_key = key
        end
      end

      trace.enable
      yield if block_given?
    ensure
      trace.disable
      execute_block(@breakpoints[prev_key][:after]) if prev_key && @breakpoints.key?(prev_key)
    end

    def all_executed?
      @breakpoints.all? do |_location, configs|
        configs.all? { |_position, config| config[:executed] }
      end
    end

    def inspect
      @breakpoints.flat_map do |location, configs|
        configs.keys.map { |position| "#{position}-#{location}" }
      end.join("|>")
    end

    private

    def set_breakpoint(path_with_line, position, &block)
      @breakpoints[path_with_line] ||= {}
      @breakpoints[path_with_line][position] = { block: block, executed: false }
    end

    def execute_block(handler)
      return unless handler
      return if handler[:executed]

      handler[:executed] = true
      handler[:block].call
    end
  end
end
