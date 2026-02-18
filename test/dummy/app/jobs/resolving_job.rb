class ResolvingJob < ApplicationJob
  include AcidicJob::Workflow

  def perform(resolve_on_first_try: true)
    @resolve_on_first_try = resolve_on_first_try

    execute_workflow(unique_by: job_id) do |w|
      w.context :resolve_data, fallback: :fetch_data
      w.step :do_something
    end
  end

  def resolve_data
    @resolve_on_first_try ? { name: "resolved" } : nil
  end

  def fetch_data
    { name: "fetched" }
  end

  def do_something
    ChaoticJob.log_to_journal!(serialize.slice("job_class", "job_id", "arguments"))
  end
end
