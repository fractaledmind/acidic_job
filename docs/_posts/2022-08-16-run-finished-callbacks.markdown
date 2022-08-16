---
layout: post
title:  "Run Finished Callbacks"
date:   2022-08-15 12:46:19 +0200
categories: features
author: Stephen Margheim
---

<p class="lead">Set callbacks for when a job run finishes fully.</p>

When working with workflow jobs that make use of the `awaits` feature for a step, it is important to remember that the `after_perform` callback will be called _as soon as the first `awaits` step has enqueued job_, and **not** when the entire job run has finished. `AcidicJob` allows the `perform` method to finish so that the queue for the workflow job is cleared to pick up new work while the `awaits` jobs are running. `AcidicJob` will automatically re-enqueue the workflow job and progress to the next step when all of the `awaits` jobs have successfully finished. However, this means that `after_perform` **is not necessarily** the same as `after_finish`. In order to provide the opportunity for you to execute callback logic _if and only if_ a job run has finished, we provide callback hooks for the `finish` event.

For example, you could use this hook to immediately clean up the `AcidicJob::Run` database record whenever the workflow job finishes successfully like so:

{% highlight ruby %}
class RideCreateJob < AcidicJob::Base
  set_callback :finish, :after, :delete_run_record

  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    with_acidic_workflow persisting: { ride: nil } do |workflow|
      step :create_ride_and_audit_record, awaits: [SomeJob.with('argument_1', keyword: 'value')]
      step :create_stripe_charge, args: [1, 2, 3], kwargs: { some: 'thing' }
      step :send_receipt
    end
  end

  private

  def delete_run_record
    return unless acidic_job_run.succeeded?

    acidic_job_run.destroy!
  end
end
{% endhighlight %}
