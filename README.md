# AcidicJob

[![Gem Version](https://badge.fury.io/rb/acidic_job.svg)](https://rubygems.org/gems/acidic_job)
[![Gem Downloads](https://img.shields.io/gem/dt/acidic_job)](https://rubygems.org/gems/acidic_job)
![Tests](https://github.com/fractaledmind/acidic_job/actions/workflows/main.yml/badge.svg)

## Idempotent operations for Rails apps (for ActiveJob or Sidekiq)

At the conceptual heart of basically any software are "operations"—the discrete actions the software performs. Rails provides a powerful abstraction layer for building operations in the form of `ActiveJob`, or we Rubyists can use the tried and true power of pure `Sidekiq`. With either we can easily trigger operations from other Ruby code throughout our Rails application (controller actions, model methods, model callbacks, etc.); we can run operations both synchronously (blocking execution and then returning its response to the caller) and asychronously (non-blocking and the caller doesn't know its response); and we can also retry a specific operation if needed seamlessly.

However, in order to ensure that our operational jobs are _robust_, we need to ensure that they are properly [idempotent and transactional](https://github.com/mperham/sidekiq/wiki/Best-Practices#2-make-your-job-idempotent-and-transactional). As stated in the [GitLab Sidekiq Style Guide](https://docs.gitlab.com/ee/development/sidekiq_style_guide.html#idempotent-jobs):

>As a general rule, a worker can be considered idempotent if:
>  * It can safely run multiple times with the same arguments.
>  * Application side-effects are expected to happen only once (or side-effects of a second run do not have an effect).

This is, of course, far easier said than done. Thus, `AcidicJob`.

`AcidicJob` provides a framework to help you make your operational jobs atomic ⚛️, consistent 🤖, isolated 🕴🏼, and durable ⛰️. Its conceptual framework is directly inspired by a truly wonderful loosely collected series of articles written by [Brandur Leach](https://twitter.com/brandur), which together lay out core techniques and principles required to make an HTTP API properly ACIDic:

1. [Building Robust Systems with ACID and Constraints](https://brandur.org/acid)
2. [Using Atomic Transactions to Power an Idempotent API](https://brandur.org/http-transactions)
3. [Transactionally Staged Job Drains in Postgres](https://brandur.org/job-drain)
4. [Implementing Stripe-like Idempotency Keys in Postgres](https://brandur.org/idempotency-keys)

Seriously, go and read these articles. `AcidicJob` brings these techniques and principles into the world of a standard Rails application, treating your background jobs like an internal API of sorts. It provides a suite of functionality that empowers you to create complex, robust, and _acidic_ jobs.

## Key Features

* **Transactional Steps**  
    break your job into a series of steps, each of which will be run within an acidic database transaction, allowing retries to jump back to the last "recovery point".
* **Steps that Await Jobs**  
    have workflow steps await other jobs, which will be enqueued and processed independently, and only when they all have finished will the parent job be re-enqueued to continue the workflow
* **Iterable Steps**  
    define steps that iterate over some collection fully until moving on to the next step
* **Persisted Attributes**  
    when retrying jobs at later steps, we need to ensure that data created in previous steps is still available to later steps on retry.
* **Transactionally Staged Jobs**  
    enqueue additional jobs within the acidic transaction safely
* **Custom Idempotency Keys**  
    use something other than the job ID for the idempotency key of the job run
* **Sidekiq Callbacks**  
    bring ActiveJob-like callbacks into your pure Sidekiq Workers
* **Run Finished Callbacks**  
    set callbacks for when a job run finishes fully

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

`AcidicJob` brings the most seamless experience when you inject it into every job in your application. This can be done most easily by simply having your `ApplicationJob` inherit from `AcidicJob::Base` (if using `ActiveJob`; inherit from `AcidicJob::ActiveKiq` if using pure Sidekiq workers):

```ruby
class ApplicationJob < AcidicJob::Base
end
```

This is useful because the module needs to be mixed into any and all jobs that you want to either [1] make acidic or [2] enqueue acidicly.

If you only want to inject `AcidicJob` into a single job, you can include our concern `AcidicJob::Mixin` instead:

```ruby
class SomeJob < ApplicationJob
  include AcidicJob::Mixin
end
```

## Key Features (in depth)


### Transactional Steps

The first and foundational feature `acidic_job` provides is the `with_acidic_workflow` method, which takes a block of transactional step methods (defined via the `step`) method:

```ruby
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
```

`with_acidic_workflow` takes only the `persisting:` named parameter (optionally) and a block (required) where you define the steps of this operation. `step` simply takes the name of a method available in the job. That's all!

Now, each execution of this job will find or create an `AcidicJob::Run` record, which we leverage to wrap every step in a database transaction. Moreover, this database record allows us to ensure that if your job fails on step 3, when it retries, it will simply jump right back to trying to execute the method defined for the 3rd step, _**and won't even execute the first two step methods**_. This means your step methods only need to be idempotent on failure, not on success, since they will never be run again if they succeed.


### Steps that Await Jobs

By simply adding the `awaits` option to your step declarations, you can attach any number of additional, asynchronous jobs to your step. This is profoundly powerful, as it means that you can define a workflow where step 2 is started _if and only if_ step 1 succeeds, but step 1 can have 3 different jobs enqueued on 3 different queues, each running in parallel. Once (and only once) all 3 jobs succeed, `AcidicJob` will re-enqueue the parent job and it will move on to step 2. That's right, you can have workers that are _executed in parallel_, **on separate queues**, and _asynchronously_, but are still **blocking**—as a group—the next step in your workflow! This unlocks incredible power and flexibility for defining and structuring complex workflows and operations.

```ruby
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
```

If you need to await a job that takes arguments, you can prepare that job along with its arguments using the `with` class method that `AcidicJob` will add to your jobs:

```ruby
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    with_acidic_workflow persisting: { ride: nil } do |workflow|
      workflow.step :create_ride_and_audit_record, awaits: awaits: [SomeJob.with('argument_1', keyword: 'value'), AnotherJob.with(1, 2, 3, some: 'thing')]
      workflow.step :create_stripe_charge
      workflow.step :send_receipt
    end
  end
end
```

If your step awaits multiple jobs (e.g. `awaits: [SomeJob, AnotherJob.with('argument_1', keyword: 'value')]`), your top level workflow job will only continue to the next step once **all** of the jobs in your `awaits` array have finished.

In some cases, you may need to _dynamically_ determine the collection of jobs that the step should wait for; in these cases, you can pass the name of a method to the `awaits` option:

```ruby
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    with_acidic_workflow persisting: { ride: nil } do |workflow|
      workflow.step :create_ride_and_audit_record, awaits: :dynamic_awaits
      workflow.step :create_stripe_charge
      workflow.step :send_receipt
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
```


### Iterable Steps

Sometimes our workflows have steps that need to iterate over a collection and perform an action for each item in the collection before moving on to the next step in the workflow. In these cases, we can use the `for_each` option when defining our step to bind that method to a specific the collection, and `AcidicJob` will pass each item into your step method for processing, keeping the same transactional guarantees as for any step. This means that if your step encounters an error in processing any item in the collection, when your job is retried, the job will jump right back to that step and right back to that item in the collection to try again.

```ruby
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
```

**Note:** This feature relies on the "Persisted Attributes" feature detailed below. This means that you can only iterate over collections that ActiveJob can serialize. See [the Rails Guide on `ActiveJob`](https://edgeguides.rubyonrails.org/active_job_basics.html#supported-types-for-arguments) for more info.


### Persisted Attributes

The `persisting` option on the `with_acidic_workflow` method allows you to create a cross-step, cross-retry context. This means that you can set an attribute in step 1, access it in step 2, have step 2 fail, have the job retry, jump directly back to step 2 on retry, and have that object still accessible. This is done by serializing all objects to a field on the `AcidicJob::Run` and manually persisting getters and setters that sync with the database record.

The default pattern you should follow when defining your `perform` method is to make any values that your `step` methods need access to, but are present at the start of the `perform` method simply instance variables. You only need to mark attributes that will be set _during a step_ via `persisting`. This means, the initial value will almost always be `nil`. If you need a default initial value, however, you can always provide that value to `persisting`.

```ruby
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
```

**Note:** This does mean that you are restricted to objects that can be serialized by **`ActiveJob`** (for more info, see [the Rails Guide on `ActiveJob`](https://edgeguides.rubyonrails.org/active_job_basics.html#supported-types-for-arguments)). This means you can persist ActiveRecord models, and any simple Ruby data types, but you can't persist things like Procs or custom class instances, for example.

**Note:** You will note the use of `self.ride = ...` in the code sample above. In order to call the attribute setter method that will sync with the database record, you _must_ use this style. `@ride = ...` and/or `ride = ...` will both fail to sync the value with the database record.


### Transactionally Staged Jobs

A standard problem when inside of database transactions is enqueuing other jobs. On the one hand, you could enqueue a job inside of a transaction that then rollbacks, which would leave that job to fail and retry and fail. On the other hand, you could enqueue a job that is picked up before the transaction commits, which would mean the records are not yet available to this job.

In order to mitigate against such issues without forcing you to use a database-backed job queue, `AcidicJob` provides `perform_acidicly` and `deliver_acidicly` methods to "transactionally stage" enqueuing other jobs from within a step (whether another `ActiveJob` or a `Sidekiq::Worker` or an `ActionMailer` delivery). These methods will create a new `AcidicJob::Run` record, but inside of the database transaction of the `step`. Upon commit of that transaction, a model callback pushes the job to your actual job queue.  Once the job has been successfully performed, the `AcidicJob::Run` record is deleted so that this table doesn't grow unbounded and unnecessarily.

```ruby
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
class ExampleJob < AcidicJob::Base
  acidic_by_job_id

  def perform
  end
end
```

Conversely, a job class can use the `acidic_by_job_arguments` method to configure that job class to use the arguments passed to the job as the foundation for the job run's idempotency key:

```ruby
class ExampleJob < AcidicJob::Base
  acidic_by_job_arguments

  def perform(arg_1, arg_2)
    # the idempotency key will be based on whatever the values of `arg_1` and `arg_2` are
  end
end
```

These options cover the two common situations, but sometimes our systems need finer-grained control. For example, our job might take some record as the job argument, but we need to use a combination of the record identifier and record status as the foundation for the idempotency key. In these cases you can pass a `Proc` or a `Block` to an `acidic_by` class method. This code will be executed in the context of the newly initialized job instance, so you will have access to whatever data the job is initialized with (like the `arguments`, for example):

```ruby
class ExampleJob < AcidicJob::Base
  acidic_by do
    record = arguments.first[:record]
    [record.id, record.status]
  end

  def perform(record:)
    # ...
  end
end
```

> **Note:** The `acidic_by` proc/block _will be executed in the context of the job instance_ at the moment the job is initialized. This means it will **not** have access to any instance variables defined in your `perform` method.


### Sidekiq Callbacks

In order to ensure that staged `AcidicJob::Run` records are only destroyed once the related job has been successfully performed, whether it is an ActiveJob or a Sidekiq Worker, `AcidicJob` also extends Sidekiq to support the [ActiveJob callback interface](https://edgeguides.rubyonrails.org/active_job_basics.html#callbacks).

This allows us to use an `after_perform` callback to delete the `AcidicJob::Run` record, whether you are using the gem with ActiveJob or pure Sidekiq Workers. Of course, this means that you can add your own callbacks to any jobs or workers that include the `AcidicJob` module as well.


### Run Finished Callbacks

When working with workflow jobs that make use of the `awaits` feature for a step, it is important to remember that the `after_perform` callback will be called _as soon as the first `awaits` step has enqueued job_, and **not** when the entire job run has finished. `AcidicJob` allows the `perform` method to finish so that the queue for the workflow job is cleared to pick up new work while the `awaits` jobs are running. `AcidicJob` will automatically re-enqueue the workflow job and progress to the next step when all of the `awaits` jobs have successfully finished. However, this means that `after_perform` **is not necessarily** the same as `after_finish`. In order to provide the opportunity for you to execute callback logic _if and only if_ a job run has finished, we provide callback hooks for the `finish` event.

For example, you could use this hook to immediately clean up the `AcidicJob::Run` database record whenever the workflow job finishes successfully like so:

```ruby
class RideCreateJob < AcidicJob::Base
  set_callback :finish, :after, :delete_run_record

  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    with_acidic_workflow persisting: { ride: nil } do |workflow|
      workflow.step :create_ride_and_audit_record, awaits: [SomeJob.with('argument_1', keyword: 'value')]
      workflow.step :create_stripe_charge, args: [1, 2, 3], kwargs: { some: 'thing' }
      workflow.step :send_receipt
    end
  end

  private

  def delete_run_record
    return unless acidic_job_run.succeeded?

    acidic_job_run.destroy!
  end
end
```


## Testing

When testing acidic jobs, you are likely to run into `ActiveRecord::TransactionIsolationError`s:

```
ActiveRecord::TransactionIsolationError: cannot set transaction isolation in a nested transaction
```

This error is thrown because by default RSpec and most MiniTest test suites use database transactions to keep the test database clean between tests. The database transaction that is wrapping all of the code executed in your test is run at the standard isolation level, but `AcidicJob` then tries to create another transaction at a more conservative isolation level. You cannot have a nested transaction that runs at a different isolation level, thus, this error. 

In order to avoid this error, you need to ensure firstly that your tests that run your acidic jobs are not using a database transaction and secondly that they use some different strategy to keep your test database clean. The [DatabaseCleaner](https://github.com/DatabaseCleaner/database_cleaner) gem is a commonly used tool to manage different strategies for keeping your test database clean. As for which strategy to use, `truncation` and `deletion` are both safe, but their speed varies based on our app's table structure (see https://github.com/DatabaseCleaner/database_cleaner#what-strategy-is-fastest). Either is fine; use whichever is faster for your app.

In order to make this test setup simpler, `AcidicJob` provides a `Testing` module that your job tests can include. It is simple; it sets `use_transactional_tests` to `false` (if the test is an `ActiveJob::TestCase`), and ensures a transaction-safe `DatabaseCleaner` strategy is run for each of your tests. Moreover, it ensures that the system's original DatabaseCleaner configuration is maintained, options included, except that any `transaction` strategies for any ORMs are replaced with a `deletion` strategy. It does so by storing whatever the system DatabaseCleaner configuration is at the start of `before_setup` phase in an instance variable and then restores that configuration at the end of `after_teardown` phase. In between, it runs the configuration thru a pipeline that selectively replaces any `transaction` strategies with a corresponding `deletion` strategy, leaving any other configured strategies untouched.

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
