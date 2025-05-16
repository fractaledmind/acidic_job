# frozen_string_literal: true

require_relative "acidic_job/version"
require_relative "acidic_job/engine"
require_relative "acidic_job/errors"
require_relative "acidic_job/builder"
require_relative "acidic_job/context"
require_relative "acidic_job/arguments"
require_relative "acidic_job/log_subscriber"
require_relative "acidic_job/workflow"

require "active_support"

module AcidicJob
  extend self

  DEFAULT_LOGGER = ActiveSupport::Logger.new($stdout)
  FINISHED_RECOVERY_POINT = "__ACIDIC_JOB_WORKFLOW_FINISHED__"

  mattr_accessor :logger, default: DEFAULT_LOGGER
  mattr_accessor :connects_to

  def instrument(channel, **options, &block)
    ActiveSupport::Notifications.instrument("#{channel}.acidic_job", **options, &block)
  end

  ActiveSupport.run_load_hooks(:acidic_job, self)
end
