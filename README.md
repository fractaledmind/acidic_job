# Acidic Job

[![Gem Version](https://badge.fury.io/rb/acidic_job.svg)](https://rubygems.org/gems/acidic_job)
[![Gem Downloads](https://img.shields.io/gem/dt/acidic_job)](https://rubygems.org/gems/acidic_job)
![Tests](https://github.com/fractaledmind/acidic_job/actions/workflows/main.yml/badge.svg)
![Coverage](https://img.shields.io/badge/code%20coverage-98%25-success)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/e0df63f7a6f141d4aecc3c477314fdb2)](https://www.codacy.com/gh/fractaledmind/acidic_job/dashboard?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=fractaledmind/acidic_job&amp;utm_campaign=Badge_Grade)
[![Sponsors](https://img.shields.io/github/sponsors/fractaledmind?color=eb4aaa&logo=GitHub%20Sponsors)](https://github.com/sponsors/fractaledmind)
[![Twitter Follow](https://img.shields.io/twitter/url?label=%40fractaledmind&style=social&url=https%3A%2F%2Ftwitter.com%2Ffractaledmind)](https://twitter.com/fractaledmind)


## Durable execution workflows for Active Job

Rails applications today frequently need to coordinate complex multi-step operations across external services, databases, and systems. While Active Job provides eventual consistency guarantees, it doesn't address the challenges of managing stateful, long-running operations that must be resilient to failures, timeouts, and partial completions. `AcidicJob` enhances Active Job with durable execution workflows that automatically track state and resiliently handle retries, while providing you the tools to ensure your operations are truly idempotent through careful state management and IO awareness.

`AcidicJob` lets you define complex workflows as a sequence of discrete, retriable steps, and by building on top of Active job you leverage your existing job infrastructure. Each step in a workflow is individually tracked and monitored, with the system maintaining consistent state even in the face of network issues, timeouts, or service outages. `AcidicJob` makes it simple to implement robust distributed operations without managing your own state machines or complex retry logic.


## Installation

Install the gem and add to the application's Gemfile by executing:

```sh
bundle add acidic_job
```

If `bundler` is not being used to manage dependencies, install the gem by executing:

```sh
gem install acidic_job
```

After installing the gem, run the installer:

```sh
rails generate acidic_job:install
```

The installer will create a migration file at `db/migrate` to setup the tables that the gem requires.


## Usage

`AcidicJob` provides a simple DSL to define linear workflows within your job. In order to define and execute a workflow within a particular job, simply `include AcidicJob::Workflow`. This will provide the `execute_workflow` method to the job, which takes a block where you define the steps of the workflow:

```ruby
class Job < ActiveJob::Base
  include AcidicJob::Workflow

  def perform
    execute_workflow do |w|
      w.step :step_1
      w.step :step_2
      w.step :step_3
    end
  end

  def step_1 = do_something
  def step_2 = do_something
  def step_3 = do_something
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

    execute_workflow do |workflow|
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

The `step` method is the only method available on the yielded workflow builder object, and it simply takes the name of a method available in the job.

> [!IMPORTANT]
> In order to craft resilient workflows, you need to ensure that each step method wraps a single unit of IO-bound work. You **must not** have a step method that performs multiple IO-bound operations, like writing to your database and calling an external API. Steps should be as granular and self-contained as possible. This allows your own logic to be more durable in case of failures in third-party APIs, network errors, and so on. So, the rule of thumb is to have only one _state mutation_ per step. And this rule of thumb graduates to a hard and fast rule for _foreign state mutations_. You **must** only have **one** foreign state mutation per step, where a foreign state mutation is any operation that writes to a system beyond your own boundaries. This might be creating a charge on Stripe, adding a DNS record, or sending an email.[^1]

[^1]: I first learned this rule from [Brandur Leach](https://twitter.com/brandur) reminds in his post on [Implementing Stripe-like Idempotency Keys in Postgres](https://brandur.org/idempotency-keys).

When your job calls `execute_workflow`, you initiate a durable execution workflow. The execution is made durable via the `AcidicJob::Execution` record that is created. This record is used to track the state of the workflow, and to ensure that if a step fails, the job can be retried and the workflow will pick up where it left off. This is a powerful feature that allows you to build resilient workflows that can handle failures gracefully, because if your job fails on step 3, when it retries, it will simply jump right back to trying to execute the method defined for the 3rd step, _**and won't even execute the first two step methods**_. This means your step methods only need to be idempotent on failure, not on success, since they will never be run again if they succeed.

By default, each step is executed and upon completion, the `AcidicJob::Execution` record is updated to reflect the completion of that step. This default makes sense for _foreign state mutations_, but for _local state mutations_, i.e. writes to your application's primary database, it makes sense to wrap the both the step execution and the record update in a single transaction. This is done by passing the `transactional` option to the `step` method:

```ruby
execute_workflow do |workflow|
  workflow.step :create_ride_and_audit_record, transactional: true
  workflow.step :create_stripe_charge
  workflow.step :send_receipt
end
```


### Persisted Attributes

In addition to the workflow steps, `AcidicJob` also provides you with an isolated context where you can persist data that is needed across steps and  across retries. This means that you can set an attribute in step 1, access it in step 2, have step 2 fail, have the job retry, jump directly back to step 2 on retry, and have that object still accessible. This is available via the `@ctx` instance variable accessible in all of your step methods:

```ruby
class RideCreateJob < AcidicJob::Base
  def perform(user_id, ride_params)
    @user = User.find(user_id)
    @params = ride_params

    execute_workflow do |workflow|
      workflow.step :create_ride_and_audit_record
      workflow.step :create_stripe_charge
      workflow.step :send_receipt
    end
  end

  def create_ride_and_audit_record
    @ctx[:ride] = @user.rides.create(@params)
  end

  def create_stripe_charge
    Stripe::Charge.create(amount: 20_00, customer: @ctx[:ride].user)
  end

  # ...
end
```

As you see, you access the `@ctx` object as if it were a hash, though it is a custom `AcidicJob::Context` object that persists the data to `AcidicJob::Value` records associated with the workflow's `AcidicJob::Execution` record.

> [!NOTE]
> This does mean that you are restricted to objects that can be serialized by **`ActiveJob`** (for more info, see [the Rails Guide on `ActiveJob`](https://edgeguides.rubyonrails.org/active_job_basics.html#supported-types-for-arguments)). This means you can persist ActiveRecord models, and any simple Ruby data types, but you can't persist things like Procs or custom class instances, for example. `AcidicJob` does, though, extend the standard set of supported types to include Active Job instances themselves, unpersisted ActiveRecord instances, and Ruby exceptions.

As the code sample also suggests, you should always use standard instance variables defined in your `perform` method when you have any values that your `step` methods need access to, but are present at the start of the `perform` method. You only need to persist attributes that will be set _during a step_ via `@ctx`.


### Custom Workflow Uniqueness

Resilient workflows must, necessarily, be idempotent.[^2] Idempotency is a fancy word that simply means your jobs need to be able to be run multiple times while any side effects only happen once. In order for your workflow executions to be idempotent, `AcidicJob` needs to know what constitutes a unique execution of your job. You can define what makes your job unique by implementing the `unique_by` method in your job:

[^2]: This is echoed both by [Mike Perham](https://www.mikeperham.com), the creator of Sidekiq, in the Sidekiq [docs on best practices](https://github.com/mperham/sidekiq/wiki/Best-Practices#2-make-your-job-idempotent-and-transactional) by the GitLab team in their [Sidekiq Style Guide](https://docs.gitlab.com/ee/development/sidekiq_style_guide.html#idempotent-jobs).

```ruby
class Job < ActiveJob::Base
  include AcidicJob::Workflow

  def unique_by
    record = arguments.first[:record]
    [record.id, record.status]
  end

  def perform(record:)
    execute_workflow do |w|
      w.step :step_1
      w.step :step_2
      w.step :step_3
    end
  end
```

> [!NOTE]
> By default, `AcidicJob` uses the job identifier provided by Active Job as the uniqueness key for the workflow execution record.

> [!TIP]
> The `unique_by` method is executed by the `execute_workflow` method. This means that it **does** have access to any instance variables defined in your `perform` method.


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

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

You can run a specific Rails version using one of the Gemfiles defined in the `/gemfiles` directory via the `BUNDLE_GEMFILE` ENV variable, e.g.:

```sh
BUNDLE_GEMFILE=gemfiles/rails_7.0.gemfile bundle exec rake test
```

You can likewise test only one particular test file using the `TEST` ENV variable, e.g.:

```sh
TEST=test/acidic_job/basics_test.rb
```

Finally, if you need to only run one particular test case itself, use the `TESTOPTS` ENV variable with the `--name` option, e.g.:

```sh
TESTOPTS="--name=test_workflow_with_each_step_succeeding"
```

You may also need to run the test suite with a particular Ruby version. If you are using the ASDF version manager, you can set the Ruby version with the `ASDF_RUBY_VERSION` ENV variable, e.g.:

```sh
ASDF_RUBY_VERSION=2.7.7 bundle exec rake test
```

If you are using `rbenv` to manage your Ruby versions, you can use the `RBENV_VERSION` ENV variable instead.

These options can of course be combined to help narrow down your debugging when you find a failing test in CI.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fractaledmind/acidic_job.
