---
layout: post
title:  "Custom Idempotency Keys"
date:   2022-08-15 12:46:19 +0200
categories: features
author: Stephen Margheim
---

<p class="lead">Use something other than the job ID for the idempotency key of the job run.</p>

By default, `AcidicJob` uses the job identifier provided by the queueing system (ActiveJob or Sidekiq) as the idempotency key for the job run. The idempotency key is what is used to guarantee that no two runs of the same job occur. However, sometimes we need particular jobs to be idempotent based on some other criteria. In these cases, `AcidicJob` provides a collection of tools to allow you to ensure the idempotency of your jobs.

Firstly, you can configure your job class to explicitly use either the job identifier or the job arguments as the foundation for the idempotency key. A job class that calls the `acidic_by_job_id` class method (which is the default behavior) will simply make the job run's idempotency key the job's identifier:

{% highlight ruby %}
class ExampleJob < AcidicJob::Base
  acidic_by_job_id

  def perform
  end
end
{% endhighlight %}

Conversely, a job class can use the `acidic_by_job_args` method to configure that job class to use the arguments passed to the job as the foundation for the job run's idempotency key:

{% highlight ruby %}
class ExampleJob < AcidicJob::Base
  acidic_by_job_args

  def perform(arg_1, arg_2)
    # the idempotency key will be based on whatever the values of `arg_1` and `arg_2` are
  end
end
{% endhighlight %}

These options cover the two common situations, but sometimes our systems need finer-grained control. For example, our job might take some record as the job argument, but we need to use a combination of the record identifier and record status as the foundation for the idempotency key. In these cases you can pass a `Proc` to an `acidic_by` class method:

{% highlight ruby %}
class ExampleJob < AcidicJob::Base
  acidic_by -> { [@record.id, @record.status] }

  def perform(record:)
    @record = record

    # the idempotency key will be based on whatever the values of `@record.id` and `@record.status` are
    with_acidic_workflow do |workflow|
      workflow.step :do_something
    end
  end
end
{% endhighlight %}

> **Note:** The `acidic_by` proc _will be executed in the context of the job instance_ at the moment the `with_acidic_workflow` method is called. This means it will have access to any instance variables defined in your `perform` method up to that point.
