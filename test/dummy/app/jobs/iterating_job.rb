class IteratingJob < ApplicationJob
  include AcidicJob::Workflow

  def perform
    @enumerable = (1..3).to_a

    execute_workflow(unique_by: job_id) do |w|
      w.step :do_something
    end
  end

  def do_something
    cursor = ctx[:cursor] || 0
    item = @enumerable[cursor]
    return if item.nil?

    # do thing with `item` idempotently
    # idempotent because journal logging is idempotent via Set
    ChaoticJob.log_to_journal!(item)

    ctx[:cursor] = cursor + 1
    repeat_step!
  end
end