require "bundler/setup"
require "active_job"
require "active_record"
require "active_support"
require "minitest/autorun"
require "logger"
require "oj"

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  enable_coverage :branch
  primary_coverage :branch
end

require "combustion"
require "sqlite3"
Combustion.path = "test/combustion"
Combustion.initialize! :active_record, :active_job

require "acidic_job"

ActiveJob::Base.logger = ActiveRecord::Base.logger = Logger.new(IO::NULL)
GlobalID.app = :test

ActiveSupport.on_load :active_job do
  self.queue_adapter = :test
end

class Performance
  def self.reset!
    @performances = 0
  end

  def self.performed!
    @performances += 1
  end

  def self.processed!(item, scope: :default)
    @processed_items ||= {}
    @processed_items[scope] ||= []
    @processed_items[scope] << item
  end

  def self.processed_items(scope = nil)
    return @processed_items if scope.nil?

    @processed_items[scope]
  end

  class << self
    attr_reader :performances
  end
end

class CodeInterceptor
  def initialize
    @breakpoints = {}
  end

  def before(path_with_line, &block)
    @breakpoints[path_with_line] ||= { before: nil }
    @breakpoints[path_with_line][:before] = block
  end

  def after(path_with_line, &block)
    @breakpoints[path_with_line] ||= { after: nil }
    @breakpoints[path_with_line][:after] = block
  end

  def enable
    prev_key = nil
    trace = TracePoint.new(:line) do |tp|
      key = "#{tp.path}:#{tp.lineno}"

      if prev_key && @breakpoints.key?(prev_key)
        @breakpoints.dig(prev_key, :after)&.call
      end

      if @breakpoints.key?(key)
        @breakpoints.dig(key, :before)&.call
      end

      prev_key = key
    end

    trace.enable
    yield if block_given?
  ensure
    trace.disable
    if prev_key && @breakpoints.key?(prev_key)
      @breakpoints.dig(prev_key, :after)&.call
    end
  end
end

$interceptor = CodeInterceptor.new

class RetryableError < StandardError; end
class DiscardableError < StandardError; end

class TestObject < ActiveRecord::Base
end

class TestEvent < ActiveRecord::Base
  belongs_to :execution, class_name: "AcidicJob::Execution"
end

class JobToTrace < ActiveJob::Base
  include AcidicJob::Workflow

  def unique_by = arguments

  def perform
    execute_workflow do |w|
      w.step :step_1
    end
  end

  def step_1 = true
end

class SimulationTests < ActiveJob::TestCase
  acidic_job_callstack = Set.new
  trace = TracePoint.new(:line) do |tp|
    next if Gem.path.any? { |path| tp.path.start_with?(path) }
    next unless tp.defined_class&.to_s&.start_with?("AcidicJob::")

    key = "#{tp.path}:#{tp.lineno}"
    desc = "#{tp.defined_class.to_s.remove("AcidicJob::")}##{tp.method_id}"

    acidic_job_callstack << [key, desc]
  end
  trace.enable { JobToTrace.perform_now }

  # {:callstack=>59, :locations=>118, :permutations=>1601496}
  error_locs = acidic_job_callstack.flat_map { |key, desc| [[:before, key, desc], [:after, key, desc]] }
  error_perms = error_locs.permutation(3)
p({callstack: acidic_job_callstack.size, locations: error_locs.size, permutations: error_perms.size})

  def before_setup
    Performance.reset!
  end

  class SimulationJob < ActiveJob::Base
    include AcidicJob::Workflow

    retry_on RetryableError
    discard_on DiscardableError

    def unique_by = arguments

    def perform(arg)
      execute_workflow do |w|
        w.step :step_1
        w.step :step_2
        w.step :step_3
      end
    end

    def step_1 = Performance.performed!
    def step_2 = Performance.performed!
    def step_3 = Performance.performed!
  end

  test "simulate a series of random errors" do
    error_perms.to_a.sample(ENV.fetch("SIMS", 100).to_i, random: Random.new(Minitest.seed)).each do |error_loc_perm|
      already_raised = [false, false, false]
      error_loc_perm.each_with_index do |(type, error_loc, _desc), i|
        $interceptor.public_send(type, error_loc) do
          if not already_raised[i]
            already_raised[i] = true
            raise RetryableError
          end
        end
      end

      job = SimulationJob.perform_later(error_loc_perm)

      events = []
      callback = lambda { |event| events << event.dup }
      ActiveSupport::Notifications.subscribed(callback, /acidic_job/) do
        $interceptor.enable do
          job.enqueue
          flush_enqueued_jobs until enqueued_jobs.empty?
        end
      end

      assert (execution_id, recover_to = AcidicJob::Execution.where(idempotency_key: job.idempotency_key).pick(:id, :recover_to))

      TestEvent.insert_all(
        events.map do |event|
          { execution_id: execution_id,
            name: event.name,
            payload: event.payload,
            started_at: event.time,
            finished_at: event.end, }
        end
      )

      assert_equal [true, true, true], already_raised
      assert_equal "FINISHED", recover_to

      logs = AcidicJob::Entry.where(execution_id: execution_id).order(timestamp: :asc).pluck(:step, :action)
      assert_equal 3, logs.count { |_, action| action == "succeeded" }
      step_logs = logs.each_with_object({}) { |(step, status), hash| (hash[step] ||= []) << status }
      step_logs.each do |step, actions|
        assert_equal 1, actions.count{ |it| it == "succeeded" }
      end
    end
  end
end