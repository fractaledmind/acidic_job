# frozen_string_literal: true

module AcidicJob
  class PluginContext
    PLUGIN_INACTIVE = :__ACIDIC_JOB_PLUGIN_INACTIVE__

    def initialize(plugin, job, execution, context, step_definition)
      @plugin = plugin
      @job = job
      @execution = execution
      @context = context
      @step_definition = step_definition
    end

    def set(hash)
      @context.set(hash)
    end

    def get(*keys)
      @context.get(*keys)
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

    def halt_workflow!
      @job.halt_workflow!
    end

    def repeat_step!
      @job.repeat_step!
    end

    def resolve_method(method_name)
      begin
        method_obj = @job.method(method_name)
      rescue NameError
        raise UndefinedMethodError.new(method_name)
      end

      method_obj
    end

    def plugin_action(action)
      "#{@plugin.keyword}/#{action}"
    end
  end
end
