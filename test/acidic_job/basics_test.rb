# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
class AcidicJob::BasicsTest < ActiveJob::TestCase
  def before_setup
    Performance.reset!
    AcidicJob::Value.delete_all
    AcidicJob::Entry.delete_all
    AcidicJob::Execution.delete_all
    TestObject.delete_all
  end

  test "workflow with each step succeeding" do
    class Job1 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2 = Performance.performed!
      def step_3 = Performance.performed!
    end

    Job1.perform_later
    flush_enqueued_jobs until enqueued_jobs.empty?

    assert_equal 3, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job1"].join("::"), execution.serialized_job["job_class"]
    assert_equal "FINISHED", execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "succeeded"],
        ["step_3", "started"],
        ["step_3", "succeeded"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )
  end

  test "workflow with retry on each step" do
    class Job2 < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = executions > 1 ? Performance.performed! : (raise DefaultsError)
      def step_2 = executions > 2 ? Performance.performed! : (raise DefaultsError)
      def step_3 = executions > 3 ? Performance.performed! : (raise DefaultsError)
    end

    Job2.perform_later
    flush_enqueued_jobs until enqueued_jobs.empty?

    assert_equal 3, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job2"].join("::"), execution.serialized_job["job_class"]
    assert_equal "FINISHED", execution.recover_to

    assert_equal 12, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "errored"],
        ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "errored"],
        ["step_2", "started"],
        ["step_2", "succeeded"],
        ["step_3", "started"],
        ["step_3", "errored"],
        ["step_3", "started"],
        ["step_3", "succeeded"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )
  end

  test "workflow with discard on step 1" do
    class Job3 < ActiveJob::Base
      include AcidicJob::Workflow

      discard_on DiscardableError

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = raise DiscardableError
      def step_2 = Performance.performed!
      def step_3 = Performance.performed!
    end

    Job3.perform_later
    flush_enqueued_jobs until enqueued_jobs.empty?

    assert_equal 0, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job3"].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_1", execution.recover_to

    assert_equal 2, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "errored"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )
  end

  test "workflow with discard on step 3" do
    class ThreeStepDiscardOnThreeJob < ActiveJob::Base
      include AcidicJob::Workflow

      discard_on DiscardableError

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2 = Performance.performed!
      def step_3 = raise DiscardableError
    end

    ThreeStepDiscardOnThreeJob.perform_later
    flush_enqueued_jobs until enqueued_jobs.empty?

    assert_equal 2, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "ThreeStepDiscardOnThreeJob"].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_3", execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "succeeded"],
        ["step_3", "started"],
        ["step_3", "errored"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )
  end

  test "workflow with error on step 3, but no rescues" do
    class Job4 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2 = Performance.performed!
      def step_3 = raise StandardError
    end

    Job4.perform_later
    assert_raises StandardError do
      flush_enqueued_jobs until enqueued_jobs.empty?
    end

    assert_equal 2, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job4"].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_3", execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "succeeded"],
        ["step_3", "started"],
        ["step_3", "errored"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )
  end

  test "workflow with database IO then error leaves behind database record" do
    class Job5 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2
        TestObject.create!
        raise StandardError
      end
      def step_3 = Performance.performed!
    end

    Job5.perform_later
    assert_raises StandardError do
      flush_enqueued_jobs until enqueued_jobs.empty?
    end

    assert_equal 1, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job5"].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_2", execution.recover_to

    assert_equal 4, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "errored"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )

    assert_equal 1, TestObject.count
  end

  test "workflow with database IO then error in transactional step leaves no database record" do
    class Job6 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2, transactional: true
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2
        TestObject.create!
        raise StandardError
      end
      def step_3 = Performance.performed!
    end

    Job6.perform_later
    assert_raises StandardError do
      flush_enqueued_jobs until enqueued_jobs.empty?
    end

    assert_equal 1, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job6"].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_2", execution.recover_to

    assert_equal 4, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "errored"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )

    assert_equal 0, TestObject.count
  end

  test "workflow with database IO then error on attempt 1 but then success leaves behind two database records" do
    class Job7 < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2
        TestObject.create!
        raise DefaultsError if executions == 1
        Performance.performed!
      end
      def step_3 = Performance.performed!
    end

    Job7.perform_later
    flush_enqueued_jobs until enqueued_jobs.empty?

    assert_equal 3, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job7"].join("::"), execution.serialized_job["job_class"]
    assert_equal "FINISHED", execution.recover_to

    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "errored"],
        ["step_2", "started"],
        ["step_2", "succeeded"],
        ["step_3", "started"],
        ["step_3", "succeeded"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )

    assert_equal 2, TestObject.count
  end

  test "workflow with database IO then error on attempt 1 but then success needs idempotency check" do
    class Job8 < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2
        TestObject.create! if not TestObject.exists?
        raise DefaultsError if executions == 1
        Performance.performed!
      end
      def step_3 = Performance.performed!
    end

    Job8.perform_later
    queries = []
    callback = lambda do |event|
      queries << event.payload.fetch(:sql)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      flush_enqueued_jobs until enqueued_jobs.empty?
    end

    assert_equal 3, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job8"].join("::"), execution.serialized_job["job_class"]
    assert_equal "FINISHED", execution.recover_to

    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "errored"],
        ["step_2", "started"],
        ["step_2", "succeeded"],
        ["step_3", "started"],
        ["step_3", "succeeded"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )

    assert_equal 1, TestObject.count

    test_object_queries = queries.select { |it| it.match?(/FROM "test_objects" | INTO "test_objects"/) }
    assert_equal 3, test_object_queries.count
    assert_equal(
      [ 'SELECT 1 AS one FROM "test_objects" LIMIT ?',
        'INSERT INTO "test_objects" DEFAULT VALUES RETURNING "id"',
        'SELECT 1 AS one FROM "test_objects" LIMIT ?' ],
      test_object_queries
    )
  end

  test "workflow with database IO then error on attempt 1 but then success needs idempotency check that can be selective" do
    class Job9 < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2
        if executions > 1
          return if TestObject.exists?
        end

        TestObject.create!
        raise DefaultsError if executions == 1
        Performance.performed!
      end
      def step_3 = Performance.performed!
    end

    Job9.perform_later
    queries = []
    callback = lambda do |event|
      queries << event.payload.fetch(:sql)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      flush_enqueued_jobs until enqueued_jobs.empty?
    end

    assert_equal 2, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job9"].join("::"), execution.serialized_job["job_class"]
    assert_equal "FINISHED", execution.recover_to

    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "errored"],
        ["step_2", "started"],
        ["step_2", "succeeded"],
        ["step_3", "started"],
        ["step_3", "succeeded"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )

    assert_equal 1, TestObject.count

    test_object_queries = queries.select { |it| it.match?(/FROM "test_objects" | INTO "test_objects"/) }
    assert_equal 2, test_object_queries.count
    assert_equal(
      [ 'INSERT INTO "test_objects" DEFAULT VALUES RETURNING "id"',
        'SELECT 1 AS one FROM "test_objects" LIMIT ?' ],
      test_object_queries
    )
  end

  test "workflow with custom idempotency key" do
    class Job10 < ActiveJob::Base
      include AcidicJob::Workflow

      def unique_by = arguments

      def perform(*args)
        execute_workflow do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1 = Performance.performed!
      def step_2 = Performance.performed!
      def step_3 = Performance.performed!
    end

    Job10.perform_later(1, 2, 3)
    flush_enqueued_jobs until enqueued_jobs.empty?

    assert_equal 3, Performance.performances
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first
    assert_equal [self.class.name, "Job10"].join("::"), execution.serialized_job["job_class"]
    assert_equal "FINISHED", execution.recover_to
    assert_equal "a615eeaee21de5179de080de8c3052c8da901138406ba71c38c032845f7d54f4", execution.idempotency_key

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [ ["step_1", "started"],
        ["step_1", "succeeded"],
        ["step_2", "started"],
        ["step_2", "succeeded"],
        ["step_3", "started"],
        ["step_3", "succeeded"] ],
      execution.entries.order(timestamp: :asc).pluck(:step, :action)
    )
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
