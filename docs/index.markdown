---
# Feel free to add content and custom Front Matter to this file.
# To modify the layout, see https://jekyllrb.com/docs/themes/#overriding-theme-defaults

layout: home
title:  "Welcome to AcidicJob"
---

<p class="lead">Idempotent operations for Rails apps (for ActiveJob or Sidekiq)</p>

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