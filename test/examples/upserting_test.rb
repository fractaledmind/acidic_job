# frozen_string_literal: true

require "test_helper"

module Examples
  class UpsertingTest < ActiveJob::TestCase
    class Job < ActiveJob::Base
    end
  end
end
