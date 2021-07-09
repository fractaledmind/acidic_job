# AcidicJob

### Idempotent operations for Rails apps, built on top of ActiveJob.

At the conceptual heart of basically any software are "operations"—the discrete actions the software performs. Rails provides a powerful abstraction layer for building operations in the form of `ActiveJob`. With `ActiveJob`, we can easily trigger from other Ruby code throughout our Rails application (controller actions, model methods, model callbacks, etc.); we can run operations both synchronously (blocking execution and then returning its response to the caller) and asychronously (non-blocking and the caller doesn't know its response); and we can also retry a specific operation if needed seemlessly.

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

`AcididJob` brings these techniques and principles into the world of a standard Rails application.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'acidic_job'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install acidic_job

Then, use the following command to copy over the AcidicJobKey migration.

```
rails generate acidic_job:key
```

## Usage

`AcidicJob` is a concern that you `include` into your operation jobs which provides two public methods to help you make your jobs idempotent and robust—`idempotently` and `step`. You can see them "in action" in the example job below:

```ruby
class RideCreateJob < ActiveJob::Base
  include AcidicJob

  def perform(ride_params)
    idempotently with: { user: current_user, params: ride_params, ride: nil } do
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

`idempotently` takes only the `with:` named parameter and a block where you define the steps of this operation. `step` simply takes the name of a method available in the job. That's all!

So, how does `AcidicJob` make this operation idempotent and robust then? In simplest form, `AcidicJob` creates an "idempotency key" record for each job run, where it stores information about that job run, like the parameters passed in and the step the job is on. It then wraps each of your step methods in a database transaction to ensure that each step in the operation is transactionally secure. Finally, it handles a variety of edge-cases and error conditions for you as well. But, basically, by explicitly breaking your operation into steps and storing a record of each job run and updating its current step as it runs, we level up the `ActiveJob` retry mechanism to ensure that we don't retry already finished steps if something goes wrong and the job has to retry. Then, by wrapping each step in a transaction, we ensure each individual step is ACIDic. Taken together, these two strategies help us to ensure that our operational jobs are both idempotent and ACIDic.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/acidic_job.
