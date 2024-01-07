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

> As a po' boy with a Nomad cluster
>
> I want just enough self-hosted GitHub runners
>
> So that I don't have to pay for them in terms of time or money

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

There were two main problems to address:

1. personal repository runners need a token scoped to a specific repository; this would create an unsustainable amount of runners if they were to be provisioned statically.
2. In order to provision them on-demand, we need to react to webhooks, which in turns requires that we expose an endpoint to a domain that GitHub can `POST` to.

### Registering runners

The first is quite simple to address.
If we emit a webhook[^GithubWebhooks] for workflow job events on a repository, the webhook payload will contain the repository name as part of the payload[^workflow_job_payload].
In order to register the runner, with the repo, we first need a _runner token_, which can be obtained via an authenticated HTTP REST call to the registration endpoint: `/repos/:owner/:repo/actions/runners/registration-token`

However, in order to _receive_ the webhook payload, we need somewhere to actually _execute_ this call.
True, we could probably set up a small action in GitHub itself to register a new runner registration token and then pass it on to whatever will create the self-hosted runner, but that would just be kicking the can down the road -- we'd eventually need a place to run a runner anyway!

So, now we start touching problem number 2 above.
We need to:

1. Register a webhook to send payload data to and endpoint
2. Receive and perform computation on the payload, extracting amongst other things the repository
3. Obtain a github token and call the runner registration endpoint
4. Start the runner with the correct parameters: url,  personal access token and labels

The first step may be large, but it is not complicated.
We can get a list of repositories, and using the [REST API](https://docs.github.com/en/rest/repos/webhooks) we can create webhooks.
However, in order to create the webhook, we need to know the destination, and it is this second item in this list is topic for the next subsection -- where do we send our payload?

### Cloudflare to the rescue

As is a well-ascertained fact by now, Hashi@home is deployed ... at home.
Like, in my private network here in my home office.
It is behind a fibre connection with no public domain resolution -- I can't just tell Github "send your payload to my place"... that's like telling someone "take this to my buddy in New York".

So, I need now some way of exposing the services running on Hashi@Home to the wider internet, by making them resolvable via DNS.
There are a few common tricks that folks have been known to play when exposing their private network to the internet, but I chose to go with Cloudflare[^whyCloudFlare] [^noAffiliation].

With a Cloudflare account, I can use the [Developer Platform](https://developers.cloudflare.com/products/?product-group=Developer+platform) and [Zero Trust](https://developers.cloudflare.com/products/?product-group=Cloudflare+One) products to[^cloudflare_developer_platform]:

* register a [DNS name](https://developers.cloudflare.com/dns/) on a domain that I own[^domain]
* attach a [worker](https://developers.cloudflare.com/workers/) to the route
* configure a [KV store](https://developers.cloudflare.com/kv/) to cache data for  the workers
* create a [tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) deploy it into the Nomad cluster at home.
* protect the tunnel with [access policies](https://developers.cloudflare.com/cloudflare-one/policies/access/) requiring a [service token](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/)

This will safely solve the problem 2 above, ensuring that webhook payloads are delivered to an endpoint which authenticates them

<pre class="mermaid">
---
title: runners workflow
flowchartConfig:
  width: 100%
---
flowchart TB
  commit(Commit)
  repo(Git Repo)
  webhook(Repo Webhook)
  action_workflow(Github Action workflow)
  action_job(Github Action job)
  runner(Github Self-Hosted runner)
  listener(Webhook receiver)
  worker([Cloudflare Worker])
  tunnel(Cloudflare tunnel)
  cf_app(Cloudflare Application)
  nomad_job(Nomad Parametrized job)
  nomad(Nomad Dispatch API)

  %% triggers %%
  subgraph Triggers["fa:fa-github Triggers"]
    direction LR
    commit-- Push update to -->repo
    commit-- Trigger -->action_workflow
  end

  %% webhook flow %%
  subgraph Webhooks
    direction TB
    repo-- Emit -->webhook
    subgraph Cloudflare["fa:fa-cloudflare"]
      direction LR
      webhook-- POST -->listener
      listener-- Route -->cf_app
      zta-- Protect -->cf_app
      cf_app-- Invoke -->worker
      worker-- POST -->tunnel
    end

    subgraph Nomad
      direction LR
      tunnel-- Expose -->nomad
      nomad-- Schedule -->nomad_job
      nomad_job-- Instantiates -->runner
    end
  end

  %% actions flow %%
  subgraph Actions["fa:fa-github Actions"]
    action_workflow-- Schedules -->action_job
    action_job-- Requests -->runner
    runner-- Executes -->action_job
    action_job-- Notifies Status -->commit
  end
</pre>


## Architecture

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
    Component(nomadJob, "Nomad Runner<br>Parametrised Job", "bash", "Nomad job to run<br>runner registration<br>and execution script")
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

---

## References and Footnotes

[^GithubWebhooks]: See [the Github docs](https://docs.github.com/en/webhooks) for a full description of Github Webhooks.
[^workflow_job_payload]: See [Webhook payload object for `workflow_job`](https://docs.github.com/en/webhooks/webhook-events-and-payloads#workflow_job)
[^whyCloudFlare]: The reasons for this basically came down to: I already have an account, I can do it for free, I wanted to learn the Cloudflare One zero trust mechanism.
[^noAffiliation]: I have no affiliation with Cloudflare other than the same consumer agreement along with all the other shmoes. I pays my money, I gets the goods.
[^domain]: I chose the `brucellino.dev` domain because reasons.
[^cloudflare_developer_platform]: The combination of all of these services was really the main reason that I chose the platform. For more information on Cloudflare products see [the docs](https://developers.cloudflare.com/)
