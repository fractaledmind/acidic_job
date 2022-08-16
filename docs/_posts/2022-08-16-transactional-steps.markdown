---
layout: post
title:  "Transactional Steps"
date:   2022-08-16 12:46:19 +0200
category: features
author: Stephen Margheim
---

<p class="lead">Break your job into a series of steps, each of which will be run within an acidic database transaction, allowing retries to jump back to the last "recovery point".</p>

The first and foundational feature **`AcidicJob`** provides is the `with_acidic_workflow` method, which takes a block of transactional step methods (defined via the `step`) method:

{% highlight ruby %}
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    with_acidic_workflow persisting: { ride: nil } do |workflow|
      workflow.step :create_ride_and_audit_record
      workflow.step :create_stripe_charge
      workflow.step :send_receipt
    end
  end

  private

  def create_ride_and_audit_record
    # ...
  end

  def create_stripe_charge
    # ...
  end

  def send_receipt
    # ...
  end
end
{% endhighlight %}

`with_acidic_workflow` takes only the `persisting:` named parameter (optionally) and a block (required) where you define the steps of this operation. `step` simply takes the name of a method available in the job. That's all!

Now, each execution of this job will find or create an `AcidicJob::Run` record, which we leverage to wrap every step in a database transaction. Moreover, this database record allows us to ensure that if your job fails on step 3, when it retries, it will simply jump right back to trying to execute the method defined for the 3rd step, _**and won't even execute the first two step methods**_. This means your step methods only need to be idempotent on failure, not on success, since they will never be run again if they succeed.
