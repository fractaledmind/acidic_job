# frozen_string_literal: true

module AcidicJob
  class Builder
    attr_reader :steps

    def initialize
      @steps = []
    end

    def step(method_name, transactional: false)
      @steps << { "does" => method_name.to_s, "transactional" => transactional }
      @steps
    end

    def define_workflow
      # [ { does: "step 1", transactional: true }, { does: "step 2", transactional: false }, ... ]
      @steps << { "does" => FINISHED_RECOVERY_POINT }

      {}.tap do |workflow|
        @steps.each_cons(2).map do |enter_step, exit_step|
          enter_name = enter_step["does"]
          workflow[enter_name] = enter_step.merge("then" => exit_step["does"])
        end
      end
      # { "step 1": { does: "step 1", transactional: true, then: "step 2" }, ...  }
    end
  end
end
