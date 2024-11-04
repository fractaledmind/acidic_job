# frozen_string_literal: true

# If you have a job that needs to be resilient, put it through the crucible.

module JobCrucible
  class RetryableError < StandardError; end

  class Simulation
    def initialize(job, test: nil, variations: 100, seed: nil, depth: 1)
      @template = job
      @test = test
      @variations = variations
      @seed = seed || Random.new_seed
      @random = Random.new(@seed)
      @depth = depth
    end

    def run(&callback)
      @template.class.retry_on RetryableError, attempts: @depth + 2, wait: 1, jitter: 0

      debug "Running #{variants.size} simulations of the total #{permutations.size} possibilities..."

      scenarios.map do |scenario|
        run_scenario(scenario, &callback)
      end
    end

    def permutations
      callstack = capture_callstack.to_a
      error_locations = callstack.map { |key, desc| ["before", key, desc] }.push ["after"] + callstack.last
      error_locations.permutation(@depth)
    end

    def variants
      return permutations if @variations.nil?

      permutations.to_a.sample(@variations, random: @random)
    end

    def scenarios
      variants.map do |glitches|
        job = clone_job_template()
        scenario = Scenario.new(job, glitches: glitches)
        job.job_id = scenario.to_s
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

      trace.enable { @template.dup.perform_now }
      @template.class.queue_adapter.enqueued_jobs = []
      @callstack
    end

    def run_scenario(scenario, &callback)
      debug "Running simulation with scenario: #{scenario}"
      @test.before_setup
      scenario.enact!
      @test.after_teardown
      callback.call(scenario)
    end

    def clone_job_template
      serialized_template = @template.serialize
      job = ActiveJob::Base.deserialize(serialized_template)
      job.exception_executions = {}
      job
    end

    def debug(...)
      @template.logger.debug(...)
    end
  end

  class Scenario
    attr_reader :events

    def initialize(job, glitches:, raise: RetryableError, capture: /active_job/)
      @job = job
      @glitches = glitches
      @raise = raise
      @capture = capture
      @glitch = nil
      @events = []
    end

    def enact!()
      @job.class.retry_on RetryableError, attempts: 10, wait: 1, jitter: 0

      ActiveSupport::Notifications.subscribed(->(event) { @events << event.dup }, @capture) do
        prepare_glitch.inject! do
          block_given? ? yield : Performance.rehearse(@job)
        end
      end
    end

    def to_s
      @glitches.map { |position, location| "#{position}-#{location}" }.join("|>")
    end

    def all_executed?
      @glitch.all_executed?
    end

    private

    def prepare_glitch
      @glitch ||= Glitch.new.tap do |glitch|
        @glitches.each do |position, location, _description|
          glitch.public_send(position, location) { raise @raise }
        end
      end
    end
  end

  class Glitch
    def initialize
      @breakpoints = {}
    end

    def before(path_with_line, &block)
      set_breakpoint(path_with_line, :before, &block)
    end

    def after(path_with_line, &block)
      set_breakpoint(path_with_line, :after, &block)
    end

    def inject!
      prev_key = nil
      trace = TracePoint.new(:line) do |tp|
        key = "#{tp.path}:#{tp.lineno}"

        begin
          execute_block(@breakpoints[prev_key][:after]) if prev_key && @breakpoints.key?(prev_key)

          execute_block(@breakpoints[key][:before]) if @breakpoints.key?(key)
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
      @breakpoints.all? do |_location, handlers|
        handlers.all? { |_position, handler| handler[:executed] }
      end
    end

    # def inspect
    #   @breakpoints.flat_map do |location, configs|
    #     configs.keys.map { |position| "#{position}-#{location}" }
    #   end.join("|>")
    # end

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

  # Performance.of(Job1).rehearse!
  class Performance
    include ActiveJob::TestHelper

    def self.rehearse(job, retry_window: 4)
      new(job, retry_window: retry_window).rehearse
    end

    def self.only_retries(job, retry_window: 4)
      new(job, retry_window: retry_window).only_retries
    end

    def self.with_future(job)
      new(job).with_future
    end

    def initialize(job, retry_window: 4)
      @job = job
      @retry_window = retry_window
    end

    def rehearse
      @job.enqueue
      perform_enqueued_jobs_with_retries
      perform_future_scheduled_jobs
    end

    def only_retries
      @job.enqueue
      perform_enqueued_jobs_with_retries
    end

    def with_future
      @job.enqueue
      perform_future_scheduled_jobs
    end

    private

    def perform_enqueued_jobs_with_retries
      retry_window = Time.now + @retry_window
      flush_enqueued_jobs(at: retry_window) until enqueued_jobs_with(at: retry_window).empty?
    end

    def perform_future_scheduled_jobs
      flush_enqueued_jobs until enqueued_jobs_with.empty?
    end
  end
end
