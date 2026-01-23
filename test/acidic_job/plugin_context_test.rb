# frozen_string_literal: true

require "test_helper"

class AcidicJob::PluginContextTest < ActiveJob::TestCase
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

      cattr_accessor :captured_step

      module CapturePlugin
        extend self
        def keyword; :capture; end
        def validate(input); input; end
        def around_step(context, &block)
          CurrentStepJob.captured_step = context.current_step
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
    assert_equal "my_step", CurrentStepJob.captured_step
  end

  test "PluginContext#entries_for_action queries entries with plugin prefix" do
    class EntriesJob < ActiveJob::Base
      include AcidicJob::Workflow

      cattr_accessor :found_entries

      module EntriesPlugin
        extend self
        def keyword; :entries_test; end
        def validate(input); input; end
        def around_step(context, &block)
          # First call records, second call should find entries
          context.record!(step: "test", action: "recorded", timestamp: Time.current)
          EntriesJob.found_entries = context.entries_for_action("recorded").count
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
    assert_equal 1, EntriesJob.found_entries
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

      cattr_accessor :action_result

      module ActionPlugin
        extend self
        def keyword; :my_plugin; end
        def validate(input); input; end
        def around_step(context, &block)
          PluginActionJob.action_result = context.plugin_action("something")
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
    assert_equal "my_plugin/something", PluginActionJob.action_result
  end

  test "PluginContext#enqueue_job enqueues the job" do
    class EnqueuePluginJob < ActiveJob::Base
      include AcidicJob::Workflow

      cattr_accessor :enqueue_called, default: false

      module EnqueuePlugin
        extend self
        def keyword; :enqueuer; end
        def validate(input); input; end
        def around_step(context, &block)
          # Enqueue a delayed retry and record that we called it
          EnqueuePluginJob.enqueue_called = true
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

    EnqueuePluginJob.enqueue_called = false
    # Use perform_now to avoid the infinite loop from perform_all_jobs
    EnqueuePluginJob.perform_now

    assert EnqueuePluginJob.enqueue_called
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

      cattr_accessor :call_count, default: 0

      module RepeatPlugin
        extend self
        def keyword; :repeater; end
        def validate(input); input; end
        def around_step(context, &block)
          RepeatPluginJob.call_count += 1
          if RepeatPluginJob.call_count < 3
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

    RepeatPluginJob.call_count = 0
    RepeatPluginJob.perform_now

    assert_equal 3, RepeatPluginJob.call_count
    assert AcidicJob::Execution.first.finished?
  end

  test "PluginContext#resolve_method returns method object" do
    class ResolveMethodJob < ActiveJob::Base
      include AcidicJob::Workflow

      cattr_accessor :resolved_method

      module ResolverPlugin
        extend self
        def keyword; :resolver; end
        def validate(input); input; end
        def around_step(context, &block)
          ResolveMethodJob.resolved_method = context.resolve_method(:my_method)
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
    assert_kind_of Method, ResolveMethodJob.resolved_method
    assert_equal "found", ResolveMethodJob.resolved_method.call
  end

  test "PluginContext#resolve_method raises UndefinedMethodError for missing method" do
    class MissingMethodJob < ActiveJob::Base
      include AcidicJob::Workflow

      cattr_accessor :raised_error

      module MissingPlugin
        extend self
        def keyword; :missing; end
        def validate(input); input; end
        def around_step(context, &block)
          begin
            context.resolve_method(:nonexistent_method)
          rescue AcidicJob::UndefinedMethodError => e
            MissingMethodJob.raised_error = e
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

    MissingMethodJob.perform_now
    assert_kind_of AcidicJob::UndefinedMethodError, MissingMethodJob.raised_error
    assert_match(/nonexistent_method/, MissingMethodJob.raised_error.message)
  end

  test "PluginContext#get delegates to context" do
    class PluginGetJob < ActiveJob::Base
      include AcidicJob::Workflow

      cattr_accessor :got_value

      module GetPlugin
        extend self
        def keyword; :getter; end
        def validate(input); input; end
        def around_step(context, &block)
          context.set(test_key: "test_value")
          PluginGetJob.got_value = context.get(:test_key)
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
    assert_equal [ "test_value" ], PluginGetJob.got_value
  end
end
