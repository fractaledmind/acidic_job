# ACIDic Jobs

## A bit about me

- programming in Ruby for 6 years
- working for test IO / EPAM
- consulting for RCRDSHP
- building Smokestack QA on the side

## Jobs are essential

- job / operation / work
- in every company, with every app, jobs are essential. Why?
- jobs are what your app *does*, expressed as a distinct unit
- jobs can be called from anywhere, run sync or async, and have retry mechanisms built-in

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
