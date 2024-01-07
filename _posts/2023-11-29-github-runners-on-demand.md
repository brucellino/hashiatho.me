---
layout: post
title: Github Runners on Nomad... on demand
date: 2023-11-20 07:00 +0100
headline: What you need, when you need it.
categories:
  - blog
tags:
  - nomad
  - terraform
  - cloudflare
mermaid: true
---

## What do I want from my runners

In the [previous post]({{ page.previous.url }}), I considered using Hashi@Home as a place to run [Self-Hosted GitHub runners](https://docs.github.com/en/actions/hosting-your-own-runners).

Before discussing problems to address, perhaps it's better to spend a few words describing how I would like my environment to _behave_ when I'm done.

My story looks a bit like this:

<pre class="">
<b>As a</b> po' boy with a Nomad cluster
<b>I want</b> just enough self-hosted GitHub runners
<b>So that</b> I don't have to pay for them in terms of time or money
</pre>
Let's take a closer look at the necessary features.

### Features

We can define three features; Runners:

1. Are On Demand
2. Scale to Zero
3. Are ephemeral

Using [gherkin syntax](https://cucumber.io/docs/gherkin/), I'll try to be a bit more explicit about what is meant by these features.

First off, runners are _on demand_:

{% highlight gherkin %}
Feature: On Demand Runner
  Runners are created based on events in the repository

  Scenario: A pull request is opened
      Given there is a webhook for pull requests
      When a pull request with an action using self-hosted runner is created
      Then a runner is created using the webhook payload

{% endhighlight %}

Furthermore, I want the runners to _scale to zero_:

{% highlight gherkin %}
Feature: Scale to Zero
  Resource consumption scales as a function of demand

  Scenario: There are no triggered workflows
      Given there are no jobs currently scheduled by workflows
      When the number of workflow jobs is zero
      Then the number of running runners on the cluster is zero

{% endhighlight %}

I also want runners to be used once and then discarded, so that I don't have to manually clean them up afterwards:

{% highlight gherkin %}
Feature: Ephemeral Runners
  Runners are used once and then discarded

  Scenario: A CI/CD job is scheduled
      Given a Github Actions workflow is triggered
      When a job is scheduled as part of the workflow
      Then the runner created is used by the job

  Scenario: A CI/CD job is completed
    Given workflow job is correctly picked up by a runner
    When the job completes
    Then the runner is deregistered and removed from the repository
{% endhighlight %}

On a finer note, I also want runners to be scheduled only when the relevant runner label is present; when the relevant label is not present, we do not create a runner.
I see this as being a part of the first feature:

{% highlight gherkin %}
Feature: On Demand Runner
    Resource consumption scales as a function of demand

    Scenario: A job is tagged as running on a self-hosted runner
        Given a job is scheduled
        When the job requests a runner with the tag "self-hosted"
        Then a runner is created using the webhook payload

    Scenario: A job not tagged as running on a self-hosted runner
        Given a job is scheduled
        When the job requests a runner with a tag not "self-hosted"
        Then no runner is created using the webhook payload
{% endhighlight %}




## Problem Statement

In this article, I'll deal with setting up a solution for provisioning GitHub runners on-demand with scale to zero.

There were two main problems to address:

1. personal repository runners need a token scoped to a specific repository; this would create an unsustainable amount of runners if they were to be provisioned statically.
2. In order to provision them on-demand, we need to react to webhooks, which in turns requires that we expose an endpoint to a domain that GitHub can `POST` to.

The solution to the first was fairly trivial,

### Cloudflare to the rescue


## Design of the solution

<div class="mermaid">
---
config:
  theme: forest
  c4:
    curve: basis
---

C4Dynamic
  title "Dynamic Diagram for Zero-Scale runner"

  Person(user, User, "A user of the repository")

  Container_Boundary(cloudflare, "Cloudflare", "Cloudflare developer platform") {
    Component(zta, "Zero Trust", "Access control mechanism<br>for authorising connections")
    Component(rbac, "RBAC", "Role-based access controls<br>for expressing access policies")
    Component(worker, "Worker", "NodeJS", "Cloudflare worker")
    Component(kv, "KV", "Cloudflare Worker <br>KV store")
    Component(domain, "Domain", "DNS", "Resolveable domain <br>on which to expose services")
  }

  Container_Boundary(github, "Github", "SCM Platform") {
    Component(repo, "Repository", "Git", "Hosts and tracks changes<br>to source code")
    Component(webhook, "Webhook", "REST", "Delivers payload based<br>on predefined triggers")
    Component(actions, "Actions", "REST", "CI/CD Workflows<br>as defined in repo")
  }

  Container_Boundary(hah, "Hashi@Home", "Compute services deployed at Home") {
    Component(nomadServer,"Nomad API", "REST", "Nomad endpoint")
    Component(nomadExec, "Nomad", "Nomad Driver", "Nomad Task<br>Executor")
  }
</div>

<!-- Rel(user,repo, "Pushes Code")
  Rel(repo, webhook, "Triggers webhook delivery")
  Rel(repo, actions, "Trigger workflow job")
  Rel(repo,domain, "Delivers Payload")
  Rel(rbac,zta, "Define Policy")
  Rel_Back(domain,zta, "Authorizes")
  Rel(worker, kv, "Lookup Data")
  Rel(domain, worker, "Triggers") -->
