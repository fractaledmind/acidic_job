# frozen_string_literal: true

require "test_helper"

class AcidicJob::BasicsTest < ActiveJob::TestCase
  test "workflow with each step succeeding" do
    class Job1 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end
      def step_2; ChaoticJob.log_to_journal!; end
      def step_3; ChaoticJob.log_to_journal!; end
    end

    Job1.perform_later
    perform_all_jobs

    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job1" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )
  end

  test "workflow with retry on each step" do
    class Job2 < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; (executions > 1) ? ChaoticJob.log_to_journal! : (raise DefaultsError); end
      def step_2; (executions > 2) ? ChaoticJob.log_to_journal! : (raise DefaultsError); end
      def step_3; (executions > 3) ? ChaoticJob.log_to_journal! : (raise DefaultsError); end
    end

    Job2.perform_later
    perform_all_jobs

    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job2" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 12, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 errored],
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 errored],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 errored],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )
  end

  test "workflow with discard on step 1" do
    class Job3 < ActiveJob::Base
      include AcidicJob::Workflow

      discard_on DiscardableError

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; raise DiscardableError; end
      def step_2; ChaoticJob.log_to_journal!; end
      def step_3; ChaoticJob.log_to_journal!; end
    end

    Job3.perform_later
    perform_all_jobs

    assert_equal 0, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job3" ].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_1", execution.recover_to

    assert_equal 2, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 errored]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )
  end

  test "workflow with discard on step 3" do
    class ThreeStepDiscardOnThreeJob < ActiveJob::Base
      include AcidicJob::Workflow

      discard_on DiscardableError

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end
      def step_2; ChaoticJob.log_to_journal!; end
      def step_3; raise DiscardableError; end
    end

    ThreeStepDiscardOnThreeJob.perform_later
    perform_all_jobs

    assert_equal 2, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "ThreeStepDiscardOnThreeJob" ].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_3", execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 errored]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )
  end

  test "workflow with error on step 3, but no rescues" do
    class Job4 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end
      def step_2; ChaoticJob.log_to_journal!; end
      def step_3; raise StandardError; end
    end

    Job4.perform_later
    assert_raises StandardError do
      perform_all_jobs
    end

    assert_equal 2, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job4" ].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_3", execution.recover_to

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 errored]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )
  end

  test "workflow with database IO then error leaves behind database record" do
    class Job5 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end

      def step_2
        Thing.create!
        raise StandardError
      end

      def step_3; ChaoticJob.log_to_journal!; end
    end

    Job5.perform_later
    assert_raises StandardError do
      perform_all_jobs
    end

    assert_equal 1, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job5" ].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_2", execution.recover_to

    assert_equal 4, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 errored]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal 1, Thing.count
  end

  test "workflow with database IO then error in transactional step leaves no database record" do
    class Job6 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2, transactional: true
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end

      def step_2
        Thing.create!
        raise StandardError
      end

      def step_3; ChaoticJob.log_to_journal!; end
    end

    Job6.perform_later
    assert_raises StandardError do
      perform_all_jobs
    end

    assert_equal 1, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job6" ].join("::"), execution.serialized_job["job_class"]
    assert_equal "step_2", execution.recover_to

    assert_equal 4, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 errored]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal 0, Thing.count
  end

  test "workflow with database IO then error on attempt 1 but then success leaves behind two database records" do
    class Job7 < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end

      def step_2
        Thing.create!
        raise DefaultsError if executions == 1

        ChaoticJob.log_to_journal!
      end

      def step_3; ChaoticJob.log_to_journal!; end
    end

    Job7.perform_later
    perform_all_jobs

    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job7" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 errored],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal 2, Thing.count
  end

  test "workflow with database IO then error on attempt 1 but then success needs idempotency check" do
    class Job8 < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end

      def step_2
        Thing.create! if !Thing.exists?
        raise DefaultsError if executions == 1

        ChaoticJob.log_to_journal!
      end

      def step_3; ChaoticJob.log_to_journal!; end
    end

    Job8.perform_later
    queries = []
    callback = lambda do |event|
      queries << event.payload.fetch(:sql)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      perform_all_jobs
    end

    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job8" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 errored],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal 1, Thing.count

    test_object_queries = queries.grep(/FROM ["`]things["`] | INTO ["`]things["`]/)

    assert_equal 3, test_object_queries.count
    assert_match(/SELECT 1 AS one FROM ["`]things["`] LIMIT ?/, test_object_queries[0])
    assert_match(/INSERT INTO ["`]things["`]/, test_object_queries[1])
    assert_match(/SELECT 1 AS one FROM ["`]things["`] LIMIT ?/, test_object_queries[2])
  end

  test "workflow with db IO then error on attempt 1 but then success needs idempotency check that can be selective" do
    class Job9 < ActiveJob::Base
      include AcidicJob::Workflow

      retry_on DefaultsError

      def perform
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end

      def step_2
        return if executions > 1 && Thing.exists?

        Thing.create!
        raise DefaultsError if executions == 1

        ChaoticJob.log_to_journal!
      end

      def step_3; ChaoticJob.log_to_journal!; end
    end

    Job9.perform_later
    queries = []
    callback = lambda do |event|
      queries << event.payload.fetch(:sql)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      perform_all_jobs
    end

    assert_equal 2, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job9" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to

    assert_equal 8, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 errored],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )

    assert_equal 1, Thing.count

    test_object_queries = queries.grep(/FROM ["`]things["`] | INTO ["`]things["`]/)

    assert_equal 2, test_object_queries.count
    assert_match(/INSERT INTO ["`]things["`]/, test_object_queries[0])
    assert_match(/SELECT 1 AS one FROM ["`]things["`] LIMIT ?/, test_object_queries[1])
  end

  test "workflow with custom idempotency key" do
    class Job10 < ActiveJob::Base
      include AcidicJob::Workflow

      def perform(*_args)
        execute_workflow(unique_by: arguments) do |w|
          w.step :step_1
          w.step :step_2
          w.step :step_3
        end
      end

      def step_1; ChaoticJob.log_to_journal!; end
      def step_2; ChaoticJob.log_to_journal!; end
      def step_3; ChaoticJob.log_to_journal!; end
    end

    Job10.perform_later(1, 2, 3)
    perform_all_jobs

    assert_equal 3, ChaoticJob.journal_size
    assert_equal 1, AcidicJob::Execution.count

    execution = AcidicJob::Execution.first

    assert_equal [ self.class.name, "Job10" ].join("::"), execution.serialized_job["job_class"]
    assert_equal AcidicJob::FINISHED_RECOVERY_POINT, execution.recover_to
    assert_equal "0ce3d65c09b390b8a53060eb6184a30d4a7025ca403b9f5aeda769932a9e2c86", execution.idempotency_key

    assert_equal 6, AcidicJob::Entry.count
    assert_equal(
      [
        %w[step_1 started],
        %w[step_1 succeeded],
        %w[step_2 started],
        %w[step_2 succeeded],
        %w[step_3 started],
        %w[step_3 succeeded]
      ],
      execution.entries.ordered.pluck(:step, :action)
    )
  end
end
