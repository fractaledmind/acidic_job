---
layout: post
title:  "Sidekiq Callbacks"
date:   2022-08-15 12:46:19 +0200
category: features
author: Stephen Margheim
---

<p class="lead">Bring ActiveJob-like callbacks into your pure Sidekiq Workers.</p>

In order to ensure that staged `AcidicJob::Run` records are only destroyed once the related job has been successfully performed, whether it is an ActiveJob or a Sidekiq Worker, `AcidicJob` also extends Sidekiq to support the [ActiveJob callback interface](https://edgeguides.rubyonrails.org/active_job_basics.html#callbacks).

This allows us to use an `after_perform` callback to delete the `AcidicJob::Run` record, whether you are using the gem with ActiveJob or pure Sidekiq Workers. Of course, this means that you can add your own callbacks to any jobs or workers that include the `AcidicJob` module as well.
