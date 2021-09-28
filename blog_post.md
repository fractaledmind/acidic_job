# ACIDic Operations in Rails

At the conceptual heart of basically any software are "operations"—the discrete actions the software performs. At the horizon of basically any software is the goal to make that sofware _robust_. Typically, one makes a software system robust by making each of its operations robust. Moreover, typically, robustness in software is considered as the software being "ACIDic"—atomic, consistent, isolated, durable.

In a loosely collected series of articles, Brandur Leach lays out the core techniques and principles required to make an HTTP API properly ACIDic:

1. https://brandur.org/acid
2. https://brandur.org/http-transactions
3. https://brandur.org/job-drain
4. https://brandur.org/idempotency-keys

With these techniques and principles in mind, our challenge is bring them into the world of a standard Rails application. This will require us to conceptually map the concepts of an HTTP request, an API server action, and an HTTP response into the world of a running Rails process.

We can begin to make this mapping by observing that an API server action is a specific instantiation of the general concept of an "operation". Like all operations, it has a "trigger" (the HTTP request) and a "response" (the HTTP response). So, what we need is a foundation upon which to build our Rails "operations".

In order to help us find that tool, let us consider the necessary characteristics we need. We need something that we can easily trigger from other Ruby code throughout our Rails application (controller actions, model methods, model callbacks, etc.). It should also be able to be run both synchronously (blocking execution and then returning its response to the caller) and asychronously (non-blocking and the caller doesn't know its response). It should then also be able to retry a specific operation (in much the way that an API consumer can "retry an operation" by hitting the same endpoint with the same request). 

As we lay out these characteristics, I imagine your mind is going where mine went—`ActiveJob` gives us a solid foundation upon which we can build "ACIDic" operations.

So, our challenge to build tooling which will allow us to make "operational" jobs _robust_.

What we need primarily is to be able to make our jobs *idempotent*, and one of the simplest yet still most powerful tools for making an operation idempotent is the idempotency key. As laid out in the article linked above, an idempotency key is a record that we store in our database to uniquely identify a particular execution of an operation and a related "recovery point" for where we are in the process of that operation.






