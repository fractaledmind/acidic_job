# frozen_string_literal: true

require "test_helper"
require "acidic_job/test_case"
require "active_job"

class ExampleJob < ActiveJob::Base
	include AcidicJob
	
	def perform
	end
end

class TestActiveJobExtension < AcidicJob::TestCase
	def test_perform_acidicly_with_idempotency_key
		ExampleJob.perform_acidicly(idempotency_key: "SOME_KEY")
	
		assert_equal 1, AcidicJob::Run.staged.count
	
		worker_run = AcidicJob::Run.staged.first
		assert_equal "SOME_KEY", worker_run.idempotency_key
	end
	
	def test_perform_acidicly_with_unique_by
		ExampleJob.perform_acidicly(unique_by: { key: "value" })
	
		assert_equal 1, AcidicJob::Run.staged.count
	
		worker_run = AcidicJob::Run.staged.first
		assert_equal "a938b14b0289740923108aa5d9efe25c2488ac2f", worker_run.idempotency_key
	end
end