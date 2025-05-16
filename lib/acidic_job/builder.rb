# frozen_string_literal: true

module AcidicJob
  class Builder
    attr_reader :steps

    def initialize(plugins)
      @plugins = plugins
      @steps = []
    end

    def step(method_name, **kwargs)
      step = { "does" => method_name.to_s }

      @plugins.each do |plugin|
        next unless kwargs.key?(plugin.keyword)

        step[plugin.keyword.to_s] = plugin.validate(kwargs[plugin.keyword])
      end

      @steps << step
      @steps
    end

    def define_workflow
      # [ { does: "step 1", transactional: true }, { does: "step 2", transactional: false }, ... ]
      @steps << { "does" => FINISHED_RECOVERY_POINT }

      definition = {
        "meta" => {
          "version" => VERSION
        },
        "steps" => {}
      }

      definition.tap do |workflow|
        @steps.each_cons(2).map do |enter_step, exit_step|
          enter_name = enter_step["does"]
          workflow["steps"][enter_name] = enter_step.merge("then" => exit_step["does"])
        end
      end
      # { meta: { ... }, steps: { "step 1": { does: "step 1", transactional: true, then: "step 2" }, ...  } }
    end
  end
end
