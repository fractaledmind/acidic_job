# AcidicJob

![main workflow](https://github.com/fractaledmind/acidic_job/actions/workflows/main.yml/badge.svg)

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

Then, use the following command to copy over the `AcidicJob::Run` migration file.

```
rails generate acidic_job:install
```

## Usage

`AcidicJob` is a concern that you `include` into your base `ApplicationJob`.

```ruby
class ApplicationJob < ActiveJob::Base
  include AcidicJob
end
```

This is useful because the module needs to be mixed into any and all jobs that you want to either make acidic or enqueue acidicly.

It provides a suite of functionality that empowers you to create complex, robust, and _acidic_ jobs.

### TL;DR

#### Key Features

* Transactional Steps — break your job into a series of steps, each of which will be run within an acidic database transaction, allowing retries to jump back to the last "recovery point".
* Persisted Attributes — when retrying jobs at later steps, we need to ensure that data created in previous steps is still available to later steps on retry.
* Transactionally Staged Jobs — enqueue additional jobs within the acidic transaction safely
* Custom Idempotency Keys — use something other than the job ID for the idempotency key of the job run
* Sidekiq Callbacks — bring ActiveJob-like callbacks into your pure Sidekiq Workers
* Sidekiq Batches — leverage the power of Sidekiq Pro's `batch` functionality without the hassle

### Transactional Steps

The first and foundational feature `acidic_job` provides is the `with_acidity` method, which takes a block of transactional step methods (defined via the `step`) method:

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob

  def perform(user_id, ride_params)
    user = User.find(user_id)

    with_acidity providing: { user: user, params: ride_params, ride: nil } do
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

`with_acidity` takes only the `providing:` named parameter and a block where you define the steps of this operation. `step` simply takes the name of a method available in the job. That's all!

Now, each execution of this job will find or create an `AcidicJob::Run` record, which we leverage to wrap every step in a database transaction. Moreover, this database record allows `acidic_job` to ensure that if your job fails on step 3, when it retries, it will simply jump right back to trying to execute the method defined for the 3rd step, and won't even execute the first two step methods. This means your step methods only need to be idempotent on failure, not on success, since they will never be run again if they succeed.

### Persisted Attributes

Any objects passed to the `providing` option on the `with_acidity` method are not just made available to each of your step methods, they are made available across retries. This means that you can set an attribute in step 1, access it in step 2, have step 2 fail, have the job retry, jump directly back to step 2 on retry, and have that object still accessible. This is done by serializing all objects to a field on the `AcidicJob::Run` and manually providing getters and setters that sync with the database record.

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob

  def perform(ride_params)
    with_acidity providing: { ride: nil } do
      step :create_ride_and_audit_record
      step :create_stripe_charge
      step :send_receipt
    end
  end

  def create_ride_and_audit_record
    self.ride = Ride.create!
  end

  def create_stripe_charge
    Stripe::Charge.create(amount: 20_00, customer: self.ride.user)
  end

  # ...
end
```

**Note:** This does mean that you are restricted to objects that can be serialized by ActiveRecord, thus no Procs, for example.

**Note:** You will note the use of `self.ride = ...` in the code sample above. In order to call the attribute setter method that will sync with the database record, you _must_ use this style. `@ride = ...` and/or `ride = ...` will both fail to sync the value with the database record.

### Transactionally Staged Jobs

A standard problem when inside of database transactions is enqueuing other jobs. On the one hand, you could enqueue a job inside of a transaction that then rollbacks, which would leave that job to fail and retry and fail. On the other hand, you could enqueue a job that is picked up before the transaction commits, which would mean the records are not yet available to this job.

In order to mitigate against such issues without forcing you to use a database-backed job queue, `acidic_job` provides `perform_acidicly` and `deliver_acidicly` methods to "transactionally stage" enqueuing other jobs from within a step (whether another ActiveJob or a Sidekiq::Worker or an ActionMailer delivery). These methods will create a new `AcidicJob::Run` record, but inside of the database transaction of the `step`. Upon commit of that transaction, a model callback pushes the job to your actual job queue.  Once the job has been successfully performed, the `AcidicJob::Run` record is deleted so that this table doesn't grow unbounded and unnecessarily.

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob

  def perform(user_id, ride_params)
    user = User.find(user_id)
    
    with_acidity providing: { user: user, params: ride_params, ride: nil } do
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
```

### Custom Idempotency Keys

By default, `AcidicJob` uses the job identifier provided by the queueing system (ActiveJob or Sidekiq) as the idempotency key for the job run. The idempotency key is what is used to guarantee that no two runs of the same job occur. However, sometimes we need particular jobs to be idempotent based on some other criteria. In these cases, `AcidicJob` provides a collection of tools to allow you to ensure the idempotency of your jobs.

Firstly, you can configure your job class to explicitly use either the job identifier or the job arguments as the foundation for the idempotency key. A job class that calls the `acidic_by_job_id` class method (which is the default behavior) will simply make the job run's idempotency key the job's identifier:

```ruby
class ExampleJob < ActiveJob::Base
  include AcidicJob
  acidic_by_job_id

  def perform
  end
end
```

Conversely, a job class can use the `acidic_by_job_args` method to configure that job class to use the arguments passed to the job as the foundation for the job run's idempotency key:

```ruby
class ExampleJob < ActiveJob::Base
  include AcidicJob
  acidic_by_job_args

  def perform(arg_1, arg_2)
    # the idempotency key will be based on whatever the values of `arg_1` and `arg_2` are
  end
end
```

These options cover the two common situations, but sometimes our systems need finer-grained control. For example, our job might take some record as the job argument, but we need to use a combination of the record identifier and record status as the foundation for the idempotency key. In these cases we can't configure the idempotency key logic at the class level, so instead we can provide the logic when enqueuing the job itself.

When you call any `deliver_acidicly` or `perform_acidicly` method you can pass an optional `unique_by` argument which will be used to generate the idempotency key:

```ruby
ExampleJob.perform_acidicly(unique_by: { id: record.id, status: record.status })
UserMailer.with(user, record).deliver_acidicly(unique_by: [user.id, record.id, record.status])
```

As you see, the value to the `unique_by` option can be a Hash or an Array or even a simple scalar value.


### Sidekiq Callbacks

In order to ensure that `AcidicJob::Staged` records are only destroyed once the related job has been successfully performed, whether it is an ActiveJob or a Sidekiq Worker, `acidic_job` also extends Sidekiq to support the [ActiveJob callback interface](https://edgeguides.rubyonrails.org/active_job_basics.html#callbacks).

This allows `acidic_job` to use an `after_perform` callback to delete the `AcidicJob::Staged` record, whether you are using the gem with ActiveJob or pure Sidekiq Workers. Of course, this means that you can add your own callbacks to any jobs or workers that include the `AcidicJob` module as well.

### Sidekiq Batches

One final feature for those of you using Sidekiq Pro: an integrated DSL for Sidekiq Batches. By simply adding the `awaits` option to your step declarations, you can attach any number of additional, asynchronous workers to your step. This is profoundly powerful, as it means that you can define a workflow where step 2 is started _if and only if_ step 1 succeeds, but step 1 can have 3 different workers enqueued on 3 different queues, each running in parallel. Once all 3 workers succeed, `acidic_job` will move on to step 2. That's right, by leveraging the power of Sidekiq Batches, you can have workers that are _executed in parallel_, **on separate queues**, and _asynchronously_, but are still **blocking**—as a group—the next step in your workflow! This unlocks incredible power and flexibility for defining and structuring complex workflows and operations, and in my mind is the number one selling point for Sidekiq Pro.

In my opinion, any commercial software using Sidekiq should get Sidekiq Pro; it is _absolutely_ worth the money. If, however, you are using `acidic_job` in a non-commercial application, you could use the open-source dropin replacement for this functionality: https://github.com/breamware/sidekiq-batch

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob

  def perform(user_id, ride_params)
    user = User.find(user_id)

    with_acidity providing: { user: user, params: ride_params, ride: nil } do
      step :create_ride_and_audit_record, awaits: [SomeJob]
      step :create_stripe_charge, args: [1, 2, 3], kwargs: { some: 'thing' }
      step :send_receipt
    end
  end
end
```

## Testing

When testing acidic jobs, you are likely to run into `ActiveRecord::TransactionIsolationError`s:

```
ActiveRecord::TransactionIsolationError: cannot set transaction isolation in a nested transaction
```

This error is thrown because by default RSpec and most MiniTest test suites use database transactions to keep the test database clean between tests. The database transaction that is wrapping all of the code executed in your test is run at the standard isolation level, but acidic jobs then try to create another transaction run at a more conservative isolation level. You cannot have a nested transaction that runs at a different isolation level, thus, this error. 

In order to avoid this error, you need to ensure firstly that your tests that run your acidic jobs are not using a database transaction and secondly that they use some different strategy to keep your test database clean. The [DatabaseCleaner](https://github.com/DatabaseCleaner/database_cleaner) gem is a commonly used tool to manage different strategies for keeping your test database clean. As for which strategy to use, `truncation` and `deletion` are both safe, but their speed varies based on our app's table structure (see https://github.com/DatabaseCleaner/database_cleaner#what-strategy-is-fastest). Either is fine; use whichever is faster for your app.

In order to make this test setup simpler, `AcidicJob` provides a `TestCase` class that your MiniTest jobs tests can inherit from. It is simple; it inherits from `ActiveJob::TestCase`, sets `use_transactional_tests` to `false`, and ensures `DatabaseCleaner` is run for each of your tests. Moreover, it ensures that the system's original DatabaseCleaner configuration is maintained, options included, except that any `transaction` strategies for any ORMs are replaced with a `deletion` strategy. It does so by storing whatever the system DatabaseCleaner configuration is at the start of `before_setup` phase in an instance variable and then restores that configuration at the end of `after_teardown` phase. In between, it runs the configuration thru a pipeline that selectively replaces any `transaction` strategies with a corresponding `deletion` strategy, leaving any other configured strategies untouched.

For those of you using RSpec, you can require the `acidic_job/rspec_configuration` file, which will configure RSpec in the exact same way I have used in my RSpec projects to allow me to test acidic jobs with either the `deletion` strategy but still have all of my other tests use the fast `transaction` strategy:

```ruby
require "database_cleaner/active_record"

# see https://github.com/DatabaseCleaner/database_cleaner#how-to-use
RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.before(:suite) do
    DatabaseCleaner.clean_with :truncation

    # Here we are defaulting to :transaction but swapping to deletion for some specs;
    # if your spec or its code-under-test uses
    # nested transactions then specify :transactional e.g.:
    #   describe "SomeWorker", :transactional do
    #
    DatabaseCleaner.strategy = :transaction

    config.before(:context, transactional: true) { DatabaseCleaner.strategy = :deletion }
    config.after(:context, transactional: true) { DatabaseCleaner.strategy = :transaction }
    config.before(:context, type: :system) { DatabaseCleaner.strategy = :deletion }
    config.after(:context, type: :system) { DatabaseCleaner.strategy = :transaction }
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/acidic_job.
