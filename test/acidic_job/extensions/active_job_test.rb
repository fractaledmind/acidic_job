# frozen_string_literal: true

require "test_helper"
require "acidic_job/test_case"
require "active_job"

class ExampleJob < ActiveJob::Base
  include AcidicJob

  def perform; end
end

class TestActiveJobExtension < AcidicJob::TestCase
end
