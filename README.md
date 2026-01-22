# 🧪 Acidic Job

[![Gem Version](https://badge.fury.io/rb/acidic_job.svg)](https://rubygems.org/gems/acidic_job)
[![Gem Downloads](https://img.shields.io/gem/dt/acidic_job)](https://rubygems.org/gems/acidic_job)
![Tests](https://github.com/fractaledmind/acidic_job/actions/workflows/main.yml/badge.svg)
![Coverage](https://img.shields.io/badge/code%20coverage-98%25-success)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/e0df63f7a6f141d4aecc3c477314fdb2)](https://www.codacy.com/gh/fractaledmind/acidic_job/dashboard?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=fractaledmind/acidic_job&amp;utm_campaign=Badge_Grade)
[![Sponsors](https://img.shields.io/github/sponsors/fractaledmind?color=eb4aaa&logo=GitHub%20Sponsors)](https://github.com/sponsors/fractaledmind)
[![Twitter Follow](https://img.shields.io/twitter/url?label=%40fractaledmind&style=social&url=https%3A%2F%2Ftwitter.com%2Ffractaledmind)](https://twitter.com/fractaledmind)

> [!WARNING]
> This is the README for the _new_ release candidate of v1, which is a major refactor from the [previous release candidate of v1](https://github.com/fractaledmind/acidic_job/tree/v1.0.0.pre29). If you are looking for the stable release, please refer to the [v0.9.0 README](https://github.com/fractaledmind/acidic_job/tree/v0.9.0).


## Durable execution workflows for Active Job

Rails applications today frequently need to coordinate complex multi-step operations across external services, databases, and systems. While Active Job provides eventual consistency guarantees, it doesn't address the challenges of managing stateful, long-running operations that must be resilient to failures, timeouts, and partial completions. `AcidicJob` enhances Active Job with durable execution workflows that automatically track state and resiliently handle retries, while providing you the tools to ensure your operations are truly idempotent through careful state management and IO awareness.

With AcidicJob, you can write reliable and repeatable multi-step distributed operations that are Atomic ⚛️, Consistent 🤖, Isolated 🕴🏼, and Durable ⛰️.


## Installation

Install the gem and add to the application's Gemfile by executing:

```sh
bundle add acidic_job --version "1.0.0.rc3"
```

If `bundler` is not being used to manage dependencies, install the gem by executing:

```sh
gem install acidic_job --pre
```

After installing the gem, run the installer:

```sh
rails generate acidic_job:install
```

The installer will create a migration file at `db/migrate` to setup the tables that the gem requires.


## Usage

`AcidicJob` provides a simple DSL to define linear workflows within your job. In order to define and execute a workflow within a particular job, simply `include AcidicJob::Workflow`. This will provide the `execute_workflow` method to the job, which takes a `unique_by` keyword argument and a block where you define the steps of the workflow:

```ruby
class Job < ActiveJob::Base
  include AcidicJob::Workflow

  def perform(arg)
    @arg = arg

    execute_workflow(unique_by: @arg) do |w|
      w.step :step_1, transactional: true
      w.step :step_2
      w.step :step_3
    end
  end

  # ...
end
```


## Key Features


### Workflow Steps

The foundational feature `AcidicJob` provides is the `execute_workflow` method, which takes a block where you define your workflow's step methods:

```ruby
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    execute_workflow(unique_by: [@user, @params]) do |workflow|
      workflow.step :create_ride_and_audit_record, transactional: true
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

> [!IMPORTANT]
> The `unique_by` keyword argument is used to define the unique identifier for a particular execution of the workflow. This helps to ensure that the workflow is idempotent, as retries of the job will correctly resume the pre-existing workflow execution. The `unique_by` argument can **only** be something that `JSON.generate(..., strict: true)` can handle; that is, it must be made up of only the JSON native types: `Hash`, `Array`, `String`, `Integer`, `Float`, `true`, `false` and `nil`.

The block passed to `execute_workflow` is where you define the steps of the workflow. Each step is defined by calling the `step` method on the yielded workflow builder object. The `step` method takes the name of a method in the job that will be executed as part of the workflow. The `transactional` keyword argument can be used to ensure that the step is executed within a database transaction.

The `step` method is the only method available on the yielded workflow builder object, and it simply takes the name of a method available in the job.

> [!IMPORTANT]
> In order to craft resilient workflows, you need to ensure that each step method wraps a single unit of IO-bound work. You **should not** have a step method that performs multiple IO-bound operations, like writing to your database and calling an external API. Steps should be as granular and self-contained as possible. This allows your own logic to be more durable in case of failures in third-party APIs, network errors, and so on. So, the rule of thumb is to have only one _state mutation_ per step. And this rule of thumb graduates to a hard and fast rule for _foreign state mutations_. You **must** only have **one** foreign state mutation per step, where a foreign state mutation is any operation that writes to a system beyond your own boundaries. This might be creating a charge on Stripe, adding a DNS record, or sending an email.[^1]

[^1]: I first learned this rule from [Brandur Leach](https://twitter.com/brandur) reminds in his post on [Implementing Stripe-like Idempotency Keys in Postgres](https://brandur.org/idempotency-keys).

When your job calls `execute_workflow`, you initiate a durable execution workflow. The execution is made durable via the `AcidicJob::Execution` record that is created. This record is used to track the state of the workflow, and to ensure that if a step fails, the job can be retried and the workflow will pick up where it left off. This is a powerful feature that allows you to build resilient workflows that can handle failures gracefully, because if your job fails on step 3, when it retries, it will simply jump right back to trying to execute the method defined for the 3rd step, _**and won't even execute the first two step methods**_. This means your step methods only need to be idempotent on failure, not on success, since they will never be run again if they succeed.

By default, each step is executed and upon completion, the `AcidicJob::Execution` record is updated to reflect the completion of that step. This default makes sense for _foreign state mutations_, but for _local state mutations_, i.e. writes to your application's primary database, it makes sense to wrap the both the step execution and the record update in a single transaction. This is done by passing the `transactional` option to the `step` method:

```ruby
execute_workflow(unique_by: [@user, @params]) do |workflow|
  workflow.step :create_ride_and_audit_record, transactional: true
  workflow.step :create_stripe_charge
  workflow.step :send_receipt
end
```


### Persisted Attributes

In addition to the workflow steps, `AcidicJob` also provides you with an isolated context where you can persist data that is needed across steps and  across retries. This means that you can set an attribute in step 1, access it in step 2, have step 2 fail, have the job retry, jump directly back to step 2 on retry, and have that object still accessible. This is available via the `ctx` object, which is an instance of `AcidicJob::Context`, in all of your step methods:

```ruby
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    execute_workflow(unique_by: [@user, @params]) do |workflow|
      workflow.step :create_ride_and_audit_record, transactional: true
      workflow.step :create_stripe_charge
      workflow.step :send_receipt
    end
  end

  def create_ride_and_audit_record
    ctx[:ride] = @user.rides.create(@params)
  end

  def create_stripe_charge
    Stripe::Charge.create(amount: 20_00, customer: ctx[:ride].user)
  end

  # ...
end
```

As you see, you access the `ctx` object as if it were a hash, though it is a custom `AcidicJob::Context` object that persists the data to `AcidicJob::Value` records associated with the workflow's `AcidicJob::Execution` record.

> [!NOTE]
> This does mean that you are restricted to objects that can be serialized by **_`ActiveJob`_** (for more info, see [the Rails Guide on `ActiveJob`](https://edgeguides.rubyonrails.org/active_job_basics.html#supported-types-for-arguments)). This means you can persist Active Record models, and any simple Ruby data types, but you can't persist things like Procs or custom class instances, for example. `AcidicJob` does, though, extend the standard set of supported types to include Active Job instances themselves, unpersisted Active Record instances, and Ruby exceptions.

As the code sample also suggests, you should always use standard instance variables defined in your `perform` method when you have any values that your `step` methods need access to, but are present at the start of the `perform` method. You only need to persist attributes that will be set _during a step_ via `ctx`.


### Custom Workflow Uniqueness

Resilient workflows must, necessarily, be idempotent.[^2] Idempotency is a fancy word that simply means your jobs need to be able to be run multiple times while any side effects only happen once. In order for your workflow executions to be idempotent, `AcidicJob` needs to know what constitutes a unique execution of your job. You can define what makes your job unique by passing the `unique_by` argument when executing the workflow:

[^2]: This is echoed both by [Mike Perham](https://www.mikeperham.com), the creator of Sidekiq, in the Sidekiq [docs on best practices](https://github.com/mperham/sidekiq/wiki/Best-Practices#2-make-your-job-idempotent-and-transactional) by the GitLab team in their [Sidekiq Style Guide](https://docs.gitlab.com/ee/development/sidekiq/idempotent_jobs.html).

```ruby
class Job < ActiveJob::Base
  include AcidicJob::Workflow

  def perform(record:)
    execute_workflow(unique_by: [record.id, record.status]) do |w|
      w.step :step_1
      w.step :step_2
      w.step :step_3
    end
  end
```

> [!TIP]
> You should think carefully about what constitutes a unique execution of a workflow. Imagine you had a workflow job for balance transers. Jill transfers $10 to John. Your system **must** be able to differentiate between retries of this transfer and new independent transfers. If you were only to use the `sender`, `recipient`, and `amount` as your `unique_by` values, then if Jill tries to transfer another $10 to John at some point in the future, that work will be considered a retry of the first transfer and not a new transfer.


### Orchestrating steps

In addition to the workflow definition setup, `AcidicJob` also provides a couple of methods to precisely control the workflow step execution. From within any step method, you can call either `repeat_step!` or `halt_workflow!`.

`repeat_step!` will cause the current step to be re-executed on the next iteration of the workflow. This is useful when you need to traverse a collection of items and perform the same operation on each item. For example, if you need to send an email to each user in a collection, you could do something like this:

```ruby
class Job < ActiveJob::Base
  include AcidicJob::Workflow

  def perform(users)
    @users = users
    execute_workflow(unique_by: @users) do |w|
      w.step :notify_users
    end
  end

  def notify_users
    cursor = ctx[:cursor] || 0
    user = @users[cursor]
    return if user.nil?

    UserMailer.with(user: user).welcome_email.deliver_later

    ctx[:cursor] = cursor + 1
    repeat_step!
  end
end
```

This example demonstrates how you can leverage the basic building blocks provided by `AcidicJob` to orchestrate complex workflows. In this case, the `notify_users` step sends an email to each user in the collection, one at a time, and resiliently handles errors by storing a cursor in the `ctx` object to keep track of the current user being processed. If any error occurs while traversing the `@users` collection, the job will be retried, and the `notify_users` step will be re-executed from the last successful cursor position.

The `halt_workflow!` method, on the other hand, stops not just the execution of the current step but the job as a whole. This is useful when you either need to conditionally stop the workflow based on some criteria or need to delay the job for some amount of time before being restarted. For example, if you need to send a follow-up email to a user 14 days after they sign up, you could do something like this:

```ruby
class Job < ActiveJob::Base
  include AcidicJob::Workflow

  def perform(user)
    @user = user
    execute_workflow(unique_by: @user) do |w|
      w.step :delay
      w.step :send_welcome_email
    end
  end

  def delay
    enqueue(wait: 14.days)
    ctx[:halt] = true
  end

  def send_welcome_email
    if ctx[:halt]
      ctx[:halt] = false
      halt_workflow!
    end
    UserMailer.with(user: @user).welcome_email.deliver_later
  end
end
```

In this example, the `delay` step creates a new instance of the job and enqueues it to run 14 days in the future. It then sets a flag in the `ctx` object to halt the job. We want to halt the job in the following step and only halt it once. This ensures that when the job is re-enqueued and performed, it jumps to the `send_welcome_email` step and that step send the email only on this second run of the job. By checking for this flag and, if it is set, clears the flag and halting the job, the `send_welcome_email` step can free the worker queue from doing work, let the system waits 2 weeks, and then pick right back up where it paused originally.


### Overview

`AcidicJob` is a library that provides a small yet powerful set of tools to build cohesive and resilient workflows in your Active Jobs. All of the tools are made available by `include`ing the `AcidicJob::Workflow` module. The primary and most important tool is the `execute_workflow` method, which you call within your `perform` method. Then, if you need to store any contextual data, you use the `ctx` objects setters and getters. Finally, within any step methods, you can call `repeat_step!` or `halt_workflow!` to control the execution of the workflow. If you need, you can also access the `execution` Active Record object to get information about the current execution of the workflow. With these lightweight tools, you can build complex workflows that are resilient to failures and can handle a wide range of use cases.


## Testing

When testing acidic jobs, you are likely to run into `ActiveRecord::TransactionIsolationError`s:

```
ActiveRecord::TransactionIsolationError: cannot set transaction isolation in a nested transaction
```

This error is thrown because by default RSpec and most MiniTest test suites use database transactions to keep the test database clean between tests. The database transaction that is wrapping all of the code executed in your test is run at the standard isolation level, but `AcidicJob` then tries to create another transaction at a more conservative isolation level. You cannot have a nested transaction that runs at a different isolation level, thus, this error.

In order to avoid this error, you need to ensure firstly that your tests that run your acidic jobs are not using a database transaction and secondly that they use some different strategy to keep your test database clean. The [DatabaseCleaner](https://github.com/DatabaseCleaner/database_cleaner) gem is a commonly used tool to manage different strategies for keeping your test database clean. As for which strategy to use, `truncation` and `deletion` are both safe, but their speed varies based on our app's table structure (see https://github.com/DatabaseCleaner/database_cleaner#what-strategy-is-fastest). Either is fine; use whichever is faster for your app.

In order to make this test setup simpler, `AcidicJob` provides a `Testing` module that your job tests can include. It is simple; it sets `use_transactional_tests` to `false` (if the test is an `ActiveJob::TestCase`), and ensures a transaction-safe `DatabaseCleaner` strategy is run for each of your tests. Moreover, it ensures that the system's original DatabaseCleaner configuration is maintained, options included, except that any `transaction` strategies for any ORMs are replaced with a `deletion` strategy. It does so by storing whatever the system DatabaseCleaner configuration is at the start of `before_setup` phase in an instance variable and then restores that configuration at the end of `after_teardown` phase. In between, it runs the configuration thru a pipeline that selectively replaces any `transaction` strategies with a corresponding `deletion` strategy, leaving any other configured strategies untouched.

For those of you using RSpec, use this as a baseline to configure RSpec in the exact same way I have used in my RSpec projects to allow me to test `AcidicJob` with the `deletion` strategy but still have all of my other tests use the fast `transaction` strategy:

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

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Running Tests

The test suite can be run against multiple databases (SQLite, MySQL, PostgreSQL). By default, tests run in parallel for speed.

```sh
bundle exec rake test           # Run all tests against all databases
bundle exec rake test:sqlite    # Run tests against SQLite only
bundle exec rake test:mysql     # Run tests against MySQL only
bundle exec rake test:postgres  # Run tests against PostgreSQL only
bundle exec rake help           # Show all available commands with examples
```

**Run a specific test file or line:**

```sh
bundle exec rake test:sqlite TEST=test/jobs/doing_job_test.rb
bundle exec rake test:sqlite TEST=test/jobs/doing_job_test.rb:10
```

**Run with a specific Rails version:**

```sh
BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile bundle exec rake test:sqlite
```

**Run with a specific Ruby version** (using ASDF or rbenv):

```sh
ASDF_RUBY_VERSION=3.2.0 bundle exec rake test
RBENV_VERSION=3.2.0 bundle exec rake test
```

### Code Coverage

To generate a coverage report, set the `COVERAGE` environment variable. This runs tests serially to ensure accurate coverage tracking:

```sh
COVERAGE=1 bundle exec rake test:sqlite
```

The HTML report is generated in the `coverage/` directory.

These options can be combined to help narrow down your debugging when you find a failing test in CI.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fractaledmind/acidic_job.
