# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require_relative "../../support/test_case"

class ExampleWorker
  include Sidekiq::Worker
  include AcidicJob

  def perform; end
end

class TestSidekiqExtension < TestCase
end
