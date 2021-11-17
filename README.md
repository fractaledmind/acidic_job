# AcidicJob

### Idempotent operations for Rails apps (for ActiveJob or Sidekiq)

At the conceptual heart of basically any software are "operations"—the discrete actions the software performs. Rails provides a powerful abstraction layer for building operations in the form of `ActiveJob`, or we Rubyists can use the tried and true power of pure `Sidekiq`. With either we can easily trigger from other Ruby code throughout our Rails application (controller actions, model methods, model callbacks, etc.); we can run operations both synchronously (blocking execution and then returning its response to the caller) and asychronously (non-blocking and the caller doesn't know its response); and we can also retry a specific operation if needed seamlessly.

However, in order to ensure that our operational jobs are _robust_, we need to ensure that they are properly [idempotent and transactional](https://github.com/mperham/sidekiq/wiki/Best-Practices#2-make-your-job-idempotent-and-transactional). As stated in the [GitLab Sidekiq Style Guide](https://docs.gitlab.com/ee/development/sidekiq_style_guide.html#idempotent-jobs):

>As a general rule, a worker can be considered idempotent if:
>  * It can safely run multiple times with the same arguments.
>  * Application side-effects are expected to happen only once (or side-effects of a second run do not have an effect).

This is, of course, far easier said than done. Thus, `AcidicJob`.

`AcidicJob` provides a framework to help you make your operational jobs atomic ⚛️, consistent 🤖, isolated 🕴🏼, and durable ⛰️. Its conceptual framework is directly inspired by a truly wonderful loosely collected series of articles written by Brandur Leach, which together lay out core techniques and principles required to make an HTTP API properly ACIDic:

1. https://brandur.org/acid
2. https://brandur.org/http-transactions
3. https://brandur.org/job-drain
4. https://brandur.org/idempotency-keys

`AcidicJob` brings these techniques and principles into the world of a standard Rails application.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'acidic_job'
```

And then execute:

    $ bundle install

Or simply execute to install the gem yourself:

    $ bundle add acidic_job

Then, use the following command to copy over the `AcidicJob::Key` migration file as well as the `AcidicJob::Staged` migration file.

```
rails generate acidic_job
```

## Usage

`AcidicJob` is a concern that you `include` into your operation jobs.

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob
end
```

It provides a suite of functionality that empowers you to create complex, robust, and _acidic_ jobs.

### Transactional Steps

The first and foundational feature `acidic_job` provides is the `with_acidity` method, which takes a block of transactional step methods (defined via the `step`) method:

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob

  def perform(ride_params)
    with_acidity given: { user: current_user, params: ride_params, ride: nil } do
      step :create_ride_and_audit_record
      step :create_stripe_charge
      step :send_receipt
    end
  end

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
```

`with_acidity` takes only the `given:` named parameter and a block where you define the steps of this operation. `step` simply takes the name of a method available in the job. That's all!

Now, each execution of this job will find or create an `AcidicJob::Key` record, which we leverage to wrap every step in a database transaction. Moreover, this database record allows `acidic_job` to ensure that if your job fails on step 3, when it retries, it will simply jump right back to trying to execute the method defined for the 3rd step, and won't even execute the first two step methods. This means your step methods only need to be idempotent on failure, not on success, since they will never be run again if they succeed.

### Persisted Attributes

Any objects passed to the `given` option on the `with_acidity` method are not just made available to each of your step methods, they are made available across retries. This means that you can set an attribute in step 1, access it in step 2, have step 2 fail, have the job retry, jump directly back to step 2 on retry, and have that object still accessible. This is done by serializing all objects to a field on the `AcidicJob::Key` and manually providing getters and setters that sync with the database record.

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob

  def perform(ride_params)
    with_acidity given: { ride: nil } do
      step :create_ride_and_audit_record
      step :create_stripe_charge
      step :send_receipt
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
```

**Note:** This does mean that you are restricted to objects that can be serialized by ActiveRecord, thus no Procs, for example.

**Note:** You will note the use of `self.ride = ...` in the code sample above. In order to call the attribute setter method that will sync with the database record, you _must_ use this style. `@ride = ...` and/or `ride = ...` will both fail to sync the value with the datbase record.

### Transactionally Staged Jobs

A standard problem when inside of database transactions is enqueuing other jobs. On the one hand, you could enqueue a job inside of a transaction that then rollbacks, which would leave that job to fail and retry and fail. On the other hand, you could enqueue a job that is picked up before the transaction commits, which would mean the records are not yet available to this job.

In order to mitigate against such issues without forcing you to use a database-backed job queue, `acidic_job` provides `perform_transactionally` and `deliver_transactionally` methods to "transactionally stage" enqueuing other jobs from within a step (whether another ActiveJob or a Sidekiq::Worker or an ActionMailer delivery). These methods will create a new `AcidicJob::Staged` record, but inside of the database transaction of the `step`. Upon commit of that transaction, a model callback pushes the job to your actual job queue.  Once the job has been successfully performed, the `AcidicJob::Staged` record is deleted so that this table doesn't grow unbounded and unnecessarily.

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob

  def perform(ride_params)
    with_acidity given: { user: current_user, params: ride_params, ride: nil } do
      step :create_ride_and_audit_record
      step :create_stripe_charge
      step :send_receipt
    end
  end

  # ...

  def send_receipt
    RideMailer.with(ride: @ride, user: @user).confirm_charge.delivery_transactionally
  end
end
```

### Sidekiq Callbacks

In order to ensure that `AcidicJob::Staged` records are only destroyed once the related job has been successfully performed, whether it is an ActiveJob or a Sidekiq Worker, `acidic_job` also extends Sidekiq to support the [ActiveJob callback interface](https://edgeguides.rubyonrails.org/active_job_basics.html#callbacks).

This allows `acidic_job` to use an `after_perform` callback to delete the `AcidicJob::Staged` record, whether you are using the gem with ActiveJob or pure Sidekiq Workers. Of course, this means that you can add your own callbacks to any jobs or workers that include the `AcidicJob` module as well.

### Sidekiq Batches

One final feature for those of you using Sidekiq Pro: an integrated DSL for Sidekiq Batches. By simply adding the `awaits` option to your step declarations, you can attach any number of additional, asynchronous workers to your step. This is profoundly powerful, as it means that you can define a workflow where step 2 is started _if and only if_ step 1 succeeds, but step 1 can have 3 different workers enqueued on 3 different queues, each running in parallel. Once all 3 workers succeed, `acidic_job` will move on to step 2. That's right, by leveraging the power of Sidekiq Batches, you can have workers that are executed in parallel, on separate queues, and asynchronously, but are still blocking—as a group—the next step in your workflow! This unlocks incredible power and flexibility for defining and structuring complex workflows and operations, and in my mind is the number one selling point for Sidekiq Pro.

In my opinion, any commercial software using Sidekiq should get Sidekiq Pro; it is _absolutely_ worth the money. If, however, you are using `acidic_job` in a non-commercial application, you could use the open-source dropin replacement for this functionality: https://github.com/breamware/sidekiq-batch

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/acidic_job.
