# frozen_string_literal: true

module AcidicJob
  class PluginContext
    PLUGIN_INACTIVE = :__ACIDIC_JOB_PLUGIN_INACTIVE__

    def initialize(plugin, job, execution, step_definition)
      @plugin = plugin
      @job = job
      @execution = execution
      @step_definition = step_definition
    end

    def definition
      @step_definition.fetch(@plugin.keyword.to_s, PLUGIN_INACTIVE)
    end

    def current_step
      @step_definition["does"]
    end

    def inactive?
      definition == PLUGIN_INACTIVE
    end

    def entries_for_action(action)
      @execution.entries.for_action(plugin_action(action))
    end

    def record!(step:, action:, timestamp:, **kwargs)
      @execution.record!(
        step: step,
        action: plugin_action(action),
        timestamp: timestamp,
        **kwargs
      )
    end

    def enqueue_job(...)
      @job.enqueue(...)
    end

    def halt_step!
      @job.halt_step!
    end

    def plugin_action(action)
      "#{@plugin.keyword}/#{action}"
    end
  end
end
