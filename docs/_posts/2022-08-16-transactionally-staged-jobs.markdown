---
layout: post
title:  "Transactionally Staged Jobs"
date:   2022-08-15 12:46:19 +0200
categories: features
author: Stephen Margheim
---

<p class="lead">Enqueue additional jobs within the acidic transaction safely.</p>

A standard problem when inside of database transactions is enqueuing other jobs. On the one hand, you could enqueue a job inside of a transaction that then rollbacks, which would leave that job to fail and retry and fail. On the other hand, you could enqueue a job that is picked up before the transaction commits, which would mean the records are not yet available to this job.

In order to mitigate against such issues without forcing you to use a database-backed job queue, `AcidicJob` provides `perform_acidicly` and `deliver_acidicly` methods to "transactionally stage" enqueuing other jobs from within a step (whether another `ActiveJob` or a `Sidekiq::Worker` or an `ActionMailer` delivery). These methods will create a new `AcidicJob::Run` record, but inside of the database transaction of the `step`. Upon commit of that transaction, a model callback pushes the job to your actual job queue.  Once the job has been successfully performed, the `AcidicJob::Run` record is deleted so that this table doesn't grow unbounded and unnecessarily.

{% highlight ruby %}
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params
    
    with_acidic_workflow persisting: { ride: nil } do |workflow|
      step :create_ride_and_audit_record
      step :create_stripe_charge
      step :send_receipt
    end
  end

  # ...

  def send_receipt
    RideMailer.with(user: @user, ride: @ride).confirm_charge.delivery_acidicly
  end
end
{% endhighlight %}
