# frozen_string_literal: true

require "active_job/queue_adapters"
require "active_job/base"
require_relative "mixin"

module AcidicJob
  class Base < ActiveJob::Base
    include Mixin
  end
end
