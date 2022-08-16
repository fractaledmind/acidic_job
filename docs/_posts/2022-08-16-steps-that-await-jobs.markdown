---
layout: post
title:  "Steps that Await Jobs"
date:   2022-08-15 12:46:19 +0200
category: features
author: Stephen Margheim
---

<p class="lead">Have workflow steps await other jobs, which will be enqueued and processed independently, and only when they all have finished will the parent job be re-enqueued to continue the workflow.</p>

By simply adding the `awaits` option to your step declarations, you can attach any number of additional, asynchronous jobs to your step. This is profoundly powerful, as it means that you can define a workflow where step 2 is started _if and only if_ step 1 succeeds, but step 1 can have 3 different jobs enqueued on 3 different queues, each running in parallel. Once (and only once) all 3 jobs succeed, `AcidicJob` will re-enqueue the parent job and it will move on to step 2. That's right, you can have workers that are _executed in parallel_, **on separate queues**, and _asynchronously_, but are still **blocking**—as a group—the next step in your workflow! This unlocks incredible power and flexibility for defining and structuring complex workflows and operations.

{% highlight ruby %}
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    with_acidic_workflow persisting: { ride: nil } do |workflow|
      workflow.step :create_ride_and_audit_record, awaits: [SomeJob, AnotherJob]
      workflow.step :create_stripe_charge
      workflow.step :send_receipt
    end
  end
end
{% endhighlight %}

If you need to await a job that takes arguments, you can prepare that job along with its arguments using the `with` class method that `AcidicJob` will add to your jobs:

{% highlight ruby %}
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    with_acidic_workflow persisting: { ride: nil } do |workflow|
      step :create_ride_and_audit_record, awaits: [
        SomeJob.with('argument_1', keyword: 'value'),
        AnotherJob.with(1, 2, 3, some: 'thing')
      ]
      step :create_stripe_charge
      step :send_receipt
    end
  end
end
{% endhighlight %}

If your step awaits multiple jobs (e.g. `awaits: [SomeJob, AnotherJob.with('argument_1', keyword: 'value')]`), your top level workflow job will only continue to the next step once **all** of the jobs in your `awaits` array have finished.

In some cases, you may need to _dynamically_ determine the collection of jobs that the step should wait for; in these cases, you can pass the name of a method to the `awaits` option:

{% highlight ruby %}
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    with_acidic_workflow persisting: { ride: nil } do |workflow|
      step :create_ride_and_audit_record, awaits: :dynamic_awaits
      step :create_stripe_charge
      step :send_receipt
    end
  end

  private

  def dynamic_awaits
    if @params["key"].present?
      [SomeJob.with('argument_1', keyword: 'value')]
    else
      [AnotherJob.with(1, 2, 3, some: 'thing')]
    end
  end
end
{% endhighlight %}
