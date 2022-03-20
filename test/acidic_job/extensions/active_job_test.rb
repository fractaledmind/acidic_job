# frozen_string_literal: true

require "test_helper"
require "active_job"
require_relative "../../support/test_case"

class ExampleJob < ActiveJob::Base
  include AcidicJob

  def perform; end
end

class TestActiveJobExtension < TestCase
end
