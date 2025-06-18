# frozen_string_literal: true

module AcidicJob
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    connects_to(**AcidicJob.connects_to) if AcidicJob.connects_to
  end
end

ActiveSupport.run_load_hooks :acidic_job_record, AcidicJob::ApplicationRecord
