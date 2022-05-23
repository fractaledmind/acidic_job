# frozen_string_literal: true

module AcidicJob
  class WorkflowBuilder
    def initialize
      @__acidic_job_steps = []
    end
  
    def step(method_name, awaits: [], for_each: nil)
      @__acidic_job_steps << {
        "does" => method_name.to_s,
        "awaits" => awaits,
        "for_each" => for_each
      }
  
      @__acidic_job_steps
    end
  
    def steps
      @__acidic_job_steps
    end
  
    def self.define_workflow(steps)
      # [ { does: "step 1", awaits: [] }, { does: "step 2", awaits: [] }, ... ]
      steps << { "does" => Run::FINISHED_RECOVERY_POINT.to_s }
  
      {}.tap do |workflow|
        steps.each_cons(2).map do |enter_step, exit_step|
          enter_name = enter_step["does"]
          workflow[enter_name] = enter_step.merge("then" => exit_step["does"])
        end
      end
      # { "step 1": { does: "step 1", awaits: [], then: "step 2" }, ...  }
    end
  end
end
