# ACIDic Jobs

  Background jobs have become an essential component of any Ruby infrastructure, and, as the Sidekiq Best Practices remind us, it is essential that jobs be "idempotent and transactional." But how do we make our jobs idempotent and transactional? In this talk, we will explore various techniques to make our jobs robust and ACIDic.

## A bit about me

  - programming in Ruby for 6 years
  - working for test IO / EPAM
  - consulting for RCRDSHP
  - building Smokestack QA on the side

## Jobs are essential

  - job / operation / worker / service
    ```ruby
      ServiceDoer.call(*arguments)
      DoJob.perform_now(*arguments)
      ServiceWorker.new.perform(*arguments)
      ServiceOperation.run(*arguments)
    ```
    * as an aside, I will state that I believe basically every use case for service objects or operation classes are better served as being ActiveJob jobs or Sidekiq workers
      + because jobs can be called from anywhere, run sync or async, and have retry mechanisms built-in
  - jobs are what your app *does*, expressed as a distinct unit
    * state mutation object
  - job == state mutation
    * for the rest of the talk, I am going to use the language of "jobs" and the interface of ActiveJob, but the principles we will be exploring apply to all of these various ways to expressing a state mutation as a Ruby object

## Jobs must be idempotent and transactional

  - when mutating state, we need to ensure integrity at each point
  - a transaction is a collection of operations, typically with ACIDic guarantees
  - ACIDic guarantees are the foundational characteristics needed for correct and precise state mutations
  - Atomic, Consistent, Isolated, Durable
    * Atomicity = everything succeeds or everything fails
    * Consistency = the data always ends up in a valid state, as defined
    * Isolation = concurrent transactions won't conflict with each other
    * Durability = once committed always committed, even with system failures
  - SQL databases give us ACIDic transactions **for free**
    * "I want to convince you that ACID databases are one of the most important tools in existence for ensuring maintainability and data correctness in big production systems"
  - Idempotency
    * computer science definition: `f(f(f(x))) == f(x)`
      + the function always, even if it's called multiple times, returns the same result
    * practical definition: An idempotent endpoint is one that can be called any number of times while guaranteeing that the side effects will occur only once.
      + at-least-once guarantee for doing work is sufficient for correctness, which is a much easier guarantee to make than at-most-once


Level 1
- wrap all database operations in a single transaction
  ```ruby
  class OpenPullRequestJob < ApplicationJob
    def perform(user, pull_request_params)
      ApplicationRecord.transaction do
        pull_request = PullRequest.create!(pull_request_params)
        WebhookEvent.create!(
          resource: :pull_request,
          action: :opened,
          payload: { pull_request: pull_request, user: user }
        )
        UserActions.create!(
          user: user,
          resource: :pull_request,
          action: :opened,
          payload: { pull_request: pull_request }
        )
      end
    end
  end
  ```
  When a user opens a pull request, we have a number of objects that we have to save in succession before finishing the request: a pull request modeling the created resource, a webhook to fire off to any listeners on the repository, a reviewer record mapping to whomever we’ve assigned review, and an event to store in the audit log.

Level 2
- handle enqueuing other jobs

Level 3
- handle foreign state mutations
  * different kinds of idempotency guarantees on the API-side
    + idempotency key
    + specified ID
    + uniqueness constraint with error
    + PUT instead of POST
  * fallback when necessary
    + GET check then POST

Level 4
- handle retries
  * with state generated in step 1 needed in step 2
  * safely finishing job on terminal error


- - -

## Jobs are internal API endpoints

- Like API endpoints, both are discrete units of work
- Like API endpoints, we should expect failure
- Like API endpoints, we should expect retries
- Like API endpoints, we should expect concurrency
- this symmetry allows us to port much of the wisdom built up over decades of building robust APIs to our app job infrastructure

## ACIDic APIs

In a loosely collected series of articles, Brandur Leach lays out the core techniques and principles required to make an HTTP API properly ACIDic:

1. https://brandur.org/acid
2. https://brandur.org/http-transactions
3. https://brandur.org/job-drain
4. https://brandur.org/idempotency-keys

His central points can be summarized as follows:

- "ACID databases are one of the most important tools in existence for ensuring maintainability and data correctness in big production systems"
- "for a common idempotent HTTP request, requests should map to backend transactions at 1:1"
- "We can dequeue jobs gracefully by using a transactionally-staged job drain."
- "Implementations that need to make synchronous changes in foreign state (i.e. outside of a local ACID store) are somewhat more difficult to design. ... To guarantee idempotency on this type of endpoint we’ll need to introduce idempotency keys."

Key concepts:

- foreign state mutations
  - The reason that the local vs. foreign distinction matters is that unlike a local set of operations where we can leverage an ACID store to roll back a result that we didn’t like, once we make our first foreign state mutation, we’re committed one way or another
- "An atomic phase is a set of local state mutations that occur in transactions between foreign state mutations."
- "A recovery point is a name of a check point that we get to after having successfully executed any atomic phase or foreign state mutation"
- "transactionally-staged job drain"
  - "With this pattern, jobs aren’t immediately sent to the job queue. Instead, they’re staged in a table within the relational database itself, and the ACID properties of the running transaction keep them invisible until they’re ready to be worked. A secondary enqueuer process reads the table and sends any jobs it finds to the job queue before removing their rows."


https://github.com/mperham/sidekiq/wiki/Best-Practices#2-make-your-job-idempotent-and-transactional

2. Make your job idempotent and transactional

Idempotency means that your job can safely execute multiple times. For instance, with the error retry functionality, your job might be half-processed, throw an error, and then be re-executed over and over until it successfully completes. Let's say you have a job which voids a credit card transaction and emails the user to let them know the charge has been refunded:

```ruby
def perform(card_charge_id)
  charge = CardCharge.find(card_charge_id)
  charge.void_transaction
  Emailer.charge_refunded(charge).deliver
end
```

What happens when the email fails to render due to a bug? Will the void_transaction method handle the case where a charge has already been refunded? You can use a database transaction to ensure data changes are rolled back if there is an error or you can write your code to be resilient in the face of errors. Just remember that Sidekiq will execute your job at least once, not exactly once.

- - -

When trying to think thru the robustness of a slice of code, I’m trying to come up with a basic checklist of things/situations to consider. Can you think of any others?

* two process are running this code at the same time
* the system shuts down during the running of this code
* an external dependency of this code behaves differently than expected
