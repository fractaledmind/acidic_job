# frozen_string_literal: true

require "test_helper"
require "acidic_job/test_case"
require "sidekiq"
require "sidekiq/testing"

class ExampleWorker
  include Sidekiq::Worker
  include AcidicJob

  def perform; end
end

class TestSidekiqExtension < AcidicJob::TestCase
end
