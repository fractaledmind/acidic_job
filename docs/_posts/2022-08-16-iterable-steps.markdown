---
layout: post
title:  "Iterable Steps"
date:   2022-08-15 12:46:19 +0200
category: features
author: Stephen Margheim
---

<p class="lead">Define steps that iterate over some collection fully until moving on to the next step.</p>

Sometimes our workflows have steps that need to iterate over a collection and perform an action for each item in the collection before moving on to the next step in the workflow. In these cases, we can use the `for_each` option when defining our step to bind that method to a specific the collection, and `AcidicJob` will pass each item into your step method for processing, keeping the same transactional guarantees as for any step. This means that if your step encounters an error in processing any item in the collection, when your job is retried, the job will jump right back to that step and right back to that item in the collection to try again.

{% highlight ruby %}
class ExampleJob < AcidicJob::Base
  def perform(record:)
    with_acidic_workflow persisting: { collection: [1, 2, 3, 4, 5] } do |workflow|
      workflow.step :process_item, for_each: :collection
      workflow.step :next_step
    end
  end

  private

  def process_item(item)
    # do whatever work needs to be done with an individual item from `collection`
  end
end
{% endhighlight %}

**Note:** This feature relies on the "Persisted Attributes" feature detailed below. This means that you can only iterate over collections that ActiveJob can serialize. See [the Rails Guide on `ActiveJob`](https://edgeguides.rubyonrails.org/active_job_basics.html#supported-types-for-arguments) for more info.
