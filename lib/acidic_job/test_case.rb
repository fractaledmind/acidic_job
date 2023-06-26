# frozen_string_literal: true

require_relative "testing"

module AcidicJob
  class TestCase < ::ActiveJob::TestCase
    include ::AcidicJob::Testing
  end
end
