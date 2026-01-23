# frozen_string_literal: true

require "test_helper"

class AcidicJob::PluginContextTest < ActiveJob::TestCase
  # Thread-local storage for capturing values from plugins during tests.
  # This approach is cleaner than cattr_accessor with manual resets and
  # is safe for parallel test execution.
  module TestCapture
    class << self
      def store
        Thread.current[:plugin_context_test_capture] ||= {}
      end

      def [](key)
        store[key]
      end

      def []=(key, value)
        store[key] = value
      end

      def clear!
        Thread.current[:plugin_context_test_capture] = {}
      end
    end
  end

  setup do
    TestCapture.clear!
  end

  test "PluginContext#set delegates to context" do
    class PluginSetJob < ActiveJob::Base
      include AcidicJob::Workflow

      module SetPlugin
        extend self
        def keyword; :setter; end
        def validate(input); input; end
        def around_step(context, &block)
          context.set(plugin_called: true)
          yield
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ SetPlugin ]) do |w|
          w.step :do_work, setter: true
        end
      end

      def do_work
        ChaoticJob.log_to_journal!({ "plugin_called" => ctx[:plugin_called] })
      end
    end

    PluginSetJob.perform_later
    perform_all_jobs

    entry = ChaoticJob.top_journal_entry
    assert_equal true, entry["plugin_called"]
  end

  test "PluginContext#current_step returns the step name" do
    class CurrentStepJob < ActiveJob::Base
      include AcidicJob::Workflow

      module CapturePlugin
        extend self
        def keyword; :capture; end
        def validate(input); input; end
        def around_step(context, &block)
          AcidicJob::PluginContextTest::TestCapture[:captured_step] = context.current_step
          yield
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ CapturePlugin ]) do |w|
          w.step :my_step, capture: true
        end
      end

      def my_step; end
    end

    CurrentStepJob.perform_now
    assert_equal "my_step", TestCapture[:captured_step]
  end

  test "PluginContext#entries_for_action queries entries with plugin prefix" do
    class EntriesJob < ActiveJob::Base
      include AcidicJob::Workflow

      module EntriesPlugin
        extend self
        def keyword; :entries_test; end
        def validate(input); input; end
        def around_step(context, &block)
          # First call records, second call should find entries
          context.record!(step: "test", action: "recorded", timestamp: Time.current)
          AcidicJob::PluginContextTest::TestCapture[:found_entries] = context.entries_for_action("recorded").count
          yield
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ EntriesPlugin ]) do |w|
          w.step :check_entries, entries_test: true
        end
      end

      def check_entries; end
    end

    EntriesJob.perform_now
    assert_equal 1, TestCapture[:found_entries]
  end

  test "PluginContext#record! creates entry with plugin-prefixed action" do
    class RecordJob < ActiveJob::Base
      include AcidicJob::Workflow

      module RecordPlugin
        extend self
        def keyword; :recorder; end
        def validate(input); input; end
        def around_step(context, &block)
          context.record!(step: "test_step", action: "custom_action", timestamp: Time.current)
          yield
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ RecordPlugin ]) do |w|
          w.step :do_record, recorder: true
        end
      end

      def do_record; end
    end

    RecordJob.perform_now

    execution = AcidicJob::Execution.first
    entry = execution.entries.find_by(action: "recorder/custom_action")
    assert_not_nil entry
    assert_equal "test_step", entry.step
  end

  test "PluginContext#plugin_action prefixes action with keyword" do
    class PluginActionJob < ActiveJob::Base
      include AcidicJob::Workflow

      module ActionPlugin
        extend self
        def keyword; :my_plugin; end
        def validate(input); input; end
        def around_step(context, &block)
          AcidicJob::PluginContextTest::TestCapture[:action_result] = context.plugin_action("something")
          yield
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ ActionPlugin ]) do |w|
          w.step :test_action, my_plugin: true
        end
      end

      def test_action; end
    end

    PluginActionJob.perform_now
    assert_equal "my_plugin/something", TestCapture[:action_result]
  end

  test "PluginContext#enqueue_job enqueues the job" do
    class EnqueuePluginJob < ActiveJob::Base
      include AcidicJob::Workflow

      module EnqueuePlugin
        extend self
        def keyword; :enqueuer; end
        def validate(input); input; end
        def around_step(context, &block)
          # Enqueue a delayed retry and record that we called it
          AcidicJob::PluginContextTest::TestCapture[:enqueue_called] = true
          context.enqueue_job(wait: 1.hour)
          context.halt_workflow!
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ EnqueuePlugin ]) do |w|
          w.step :will_enqueue, enqueuer: true
        end
      end

      def will_enqueue; end
    end

    # Use perform_now to avoid the infinite loop from perform_all_jobs
    EnqueuePluginJob.perform_now

    assert TestCapture[:enqueue_called]
    # Should have enqueued a delayed job
    assert_equal 1, enqueued_jobs.size
  end

  test "PluginContext#halt_workflow! halts the workflow" do
    class HaltPluginJob < ActiveJob::Base
      include AcidicJob::Workflow

      module HaltPlugin
        extend self
        def keyword; :halter; end
        def validate(input); input; end
        def around_step(context, &block)
          context.halt_workflow!
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ HaltPlugin ]) do |w|
          w.step :will_halt, halter: true
          w.step :never_reached
        end
      end

      def will_halt
        raise "Should not reach here"
      end

      def never_reached
        raise "Should not reach here"
      end
    end

    HaltPluginJob.perform_now

    execution = AcidicJob::Execution.first
    # Should be halted, not finished
    assert_equal "will_halt", execution.recover_to
    assert execution.entries.exists?(action: "halted")
  end

  test "PluginContext#repeat_step! repeats the current step" do
    class RepeatPluginJob < ActiveJob::Base
      include AcidicJob::Workflow

      module RepeatPlugin
        extend self
        def keyword; :repeater; end
        def validate(input); input; end
        def around_step(context, &block)
          AcidicJob::PluginContextTest::TestCapture[:call_count] ||= 0
          AcidicJob::PluginContextTest::TestCapture[:call_count] += 1
          if AcidicJob::PluginContextTest::TestCapture[:call_count] < 3
            context.repeat_step!
          else
            yield
          end
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ RepeatPlugin ]) do |w|
          w.step :will_repeat, repeater: true
        end
      end

      def will_repeat; end
    end

    RepeatPluginJob.perform_now

    assert_equal 3, TestCapture[:call_count]
    assert AcidicJob::Execution.first.finished?
  end

  test "PluginContext#resolve_method returns method object" do
    class ResolveMethodJob < ActiveJob::Base
      include AcidicJob::Workflow

      module ResolverPlugin
        extend self
        def keyword; :resolver; end
        def validate(input); input; end
        def around_step(context, &block)
          AcidicJob::PluginContextTest::TestCapture[:resolved_method] = context.resolve_method(:my_method)
          yield
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ ResolverPlugin ]) do |w|
          w.step :test_resolve, resolver: true
        end
      end

      def test_resolve; end
      def my_method; "found"; end
    end

    ResolveMethodJob.perform_now
    assert_kind_of Method, TestCapture[:resolved_method]
    assert_equal "found", TestCapture[:resolved_method].call
  end

  test "PluginContext#resolve_method raises UndefinedMethodError for missing method" do
    class PluginContextMissingMethodJob < ActiveJob::Base
      include AcidicJob::Workflow

      module MissingPlugin
        extend self
        def keyword; :missing; end
        def validate(input); input; end
        def around_step(context, &block)
          begin
            context.resolve_method(:nonexistent_method)
          rescue AcidicJob::UndefinedMethodError => e
            AcidicJob::PluginContextTest::TestCapture[:raised_error] = e
          end
          yield
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ MissingPlugin ]) do |w|
          w.step :test_missing, missing: true
        end
      end

      def test_missing; end
    end

    PluginContextMissingMethodJob.perform_now
    assert_kind_of AcidicJob::UndefinedMethodError, TestCapture[:raised_error]
    assert_match(/nonexistent_method/, TestCapture[:raised_error].message)
  end

  test "PluginContext#get delegates to context" do
    class PluginGetJob < ActiveJob::Base
      include AcidicJob::Workflow

      module GetPlugin
        extend self
        def keyword; :getter; end
        def validate(input); input; end
        def around_step(context, &block)
          context.set(test_key: "test_value")
          AcidicJob::PluginContextTest::TestCapture[:got_value] = context.get(:test_key)
          yield
        end
      end

      def perform
        execute_workflow(unique_by: job_id, with: [ GetPlugin ]) do |w|
          w.step :do_get, getter: true
        end
      end

      def do_get; end
    end

    PluginGetJob.perform_now
    assert_equal [ "test_value" ], TestCapture[:got_value]
  end
end
