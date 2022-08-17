---
layout: post
title:  "Persisted Attributes"
date:   2022-08-15 12:46:19 +0200
category: features
author: Stephen Margheim
---

<p class="lead">When retrying jobs at later steps, we need to ensure that data created in previous steps is still available to later steps on retry.</p>

The `persisting` option on the `with_acidic_workflow` method allows you to create a cross-step, cross-retry context. This means that you can set an attribute in step 1, access it in step 2, have step 2 fail, have the job retry, jump directly back to step 2 on retry, and have that object still accessible. This is done by serializing all objects to a field on the `AcidicJob::Run` and manually persisting getters and setters that sync with the database record.

The default pattern you should follow when defining your `perform` method is to make any values that your `step` methods need access to, but are present at the start of the `perform` method simply instance variables. You only need to mark attributes that will be set _during a step_ via `persisting`. This means, the initial value will almost always be `nil`. If you need a default initial value, however, you can always provide that value to `persisting`.

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

  def create_ride_and_audit_record
    self.ride = Ride.create!
  end

  def create_stripe_charge
    Stripe::Charge.create(amount: 20_00, customer: @ride.user)
  end

  # ...
end
{% endhighlight %}

**Note:** This does mean that you are restricted to objects that can be serialized by **`ActiveJob`** (for more info, see [the Rails Guide on `ActiveJob`](https://edgeguides.rubyonrails.org/active_job_basics.html#supported-types-for-arguments)). This means you can persist ActiveRecord models, and any simple Ruby data types, but you can't persist things like Procs or custom class instances, for example.

**Note:** You will note the use of `self.ride = ...` in the code sample above. In order to call the attribute setter method that will sync with the database record, you _must_ use this style. `@ride = ...` and/or `ride = ...` will both fail to sync the value with the database record.
