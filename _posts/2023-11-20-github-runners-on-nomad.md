---
layout: post
title: Github Runners on Nomad
date: 2023-11-20 07:00 +0100
headline: Finally, something actually useful!
categories:
  - blog
tags:
  - nomad
  - terraform
---

<figure class="figure">
  <img src="{{ site.url }}/assets/img/test-all-the-things.jpg" width="33%">
</figure>

## Test ALL THE THINGS

If you're like me, you have a bunch of repositories with bits of infrastructure and they take care and feeding.
Once things become stable and usable, one ends up mainly having to deal with dependency updates, which has been made immeasurably easier now that we have nice things like [dependabot](https://github.blog/2023-01-12-a-smarter-quieter-dependabot/) and [Mend Renovate](https://www.mend.io/renovate/).
Our robot sidekicks keep an eye out for vulnerabilities or udpates in our dependencies, and when they spot them, they send us a nice pull request for us to merge.
Of course, they can't be sure that the change will actually work for our use case, so we still have to test our usage of they new shiny, but hey, that's what CI is for right?
If you, like me, have set up some form of continuous integration pipeline for these incoming change proposals, you can run whatever checks you need to determine whether what the robots are sending you is a good idea, or whether they should politely told no thanks this time.
Github Actions is a great way to declare these CI steps and provide some continuous feedback on the validity of these proposals -- just run the CI pipeline on every PR and see what happens!
If the build breaks, the proposal is no good -- but no worries, the robots will keep trying when it's rebased eventually.

---

<figure class="figure">
  <img src="{{ site.url }}/assets/img/sad-test-all-the-things.jpg" width="33%">
</figure>

## Test all the things

Now, herein lies the rub: if you have an Ansible role or a Terraform module or a Cloudflare function, which are most of my toys, you're going to end up declaring dependency on a bunch of pips (via `requirements.txt`) or maybe a few other roles via a `requirements.yml`, a bunch of providers or modules in your `.tf` and `.tf.lock` files, or a bunch of NPM packages in `package.json`.
If you want a really stable environment, you'll go and pin every single one of those dependencies to an exact version, and then religiously test every change that's proposed.
Pinning every single package severely reduces the space of available permutations which can solve a given combination, but also makes it far more likely that atomic changes will have to be made.

Of course, packages change at different rates, with some having a faster release cadence than others, so it's not as if I need to test all \\(N\\) changes every day, week _etc_.
Nonetheless, it often so happens that several PRs will be opened by Renovate at the same time in a repo of mine, triggering action runs for each of them.

A common scenario is that an underlying package, which I do not explicitly depend on, is updated, triggering version bumps in several on which I _do_ explicitly depend.
This creates, let's say \\((N\\) pull requests.
Another common scenario is the discovery of a CVE which affects \\(N\\) packages, all of which have version bumps at the same time, triggering the same `N` pull requests.

When one of them is merged, Renovate rebases the rest of them, triggering a new set of actions by default -- thus instead of testing \\(N)\\) changes, I end up testing \\(N(N-1)\over2\\) changes instead of \\(N\\).
This is \\(O(N^2)\\) instead of \\(O(N)\\).

## The actual problem

Long story short, for \\(M\\) repos, I end up running \\(O(N^2)\times M\\) for \\(N\\) changes, which ends up exhausting the [Github actions free tier limit of 2000 CI/CD minutes a month](https://github.com/pricing).

So: either I can get 50k CI/CD minutes/month with a GitHub Enterprise account, which seems like overkill and will cost USD 250 p.a. or I can use [self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners).

Hashi@home would be great for this - I already have it, for one thing, and  I already have a platform running on it.
In particular, the compute modules would be well-suited to running these kinds of workloads.
The general approach would be to write a Nomad job to run the runner.
The token could be generated with a script, or terraformed somehow, and passed into the runner via a Vault secret claim.
A few initial manual tests[^runner_instructions] showed that this indeed worked: after generating a GitHub runner token, I ran the `run.sh` script with the token.
Just as expected, a runner came up green and waited for jobs.

Nice!

I could just start the runners and let GitHub do its thing
The more I thought about it, the simpler it seemed - just create a runner on each node and wait for jobs... how hard could it be?

### Just an implementation detail

Well, it turns out that I would have to address a few details related to how GitHub manages self-hosted runners.

#### Org runners

For one thing, I couldn't create runner groups, since these are only available for the "GitHub Team"  plan, so I would have to add runners to a "default" group at the org level.
While not terrible, it still wasn't great.

I ended up with a Nomad job template which was invoked via Terraform.

I'd need the following providers:

- **`vault`** for storing the generated runner registration tokens and configuring the other providers
- **`github`** for looking up org endpoints
- **`http`** for registering the runners via the GitHub runners[^no_endpoint]
- **`nomad`** for registering the actual runner job.

{% highlight hcl %}
terraform {
  backend "consul" {
    scheme = "http"
    path   = "terraform/personal/github-runners"
  }
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.0"
    }
  }
}
{% endhighlight %}

Next, I'd need to declare which Orgs I wanted runners for:

{% highlight hcl %}
variable "orgs" {
  description = "Names of the Github organisations"
  default     = ["AAROC", "Hashi-at-Home", "SouthAfricaDigitalScience"]
  sensitive   = false
  type        = set(string)
}
{% endhighlight %}

and look them up with a `data.github_organization` loop

{% highlight hcl %}
data "github_organization" "selected" {
  for_each = var.orgs
  name     = each.value
}
{% endhighlight %}

First, however, I'd need to configure the GitHub provider with a GitHub token from Vault:

{% highlight hcl %}
provider "vault" {}

data "vault_kv_secret_v2" "name" {
  mount = "kv"
  name  = "github"
}

provider "github" {
  token = data.vault_kv_secret_v2.name.data.org_scope
}

{% endhighlight %}

The runners could then be registered via an authenticated [REST API call](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-a-registration-token-for-an-organization):

{% highlight hcl %}
provider "http" {}

locals {
  headers = {
    "Accept"               = "application/vnd.github+json"
    "Authorization"        = "Bearer ${data.vault_kv_secret_v2.name.data.org_scope}"
    "X-GitHub-Api-Version" = "2022-11-28"
  }
}

data "http" "runner_reg_token" {
  for_each = data.github_organization.selected
  url             = "https://api.github.com/orgs/${each.value.orgname}/actions/runners/registration-token"
  request_headers = local.headers
  method          = "POST"
  lifecycle {
    postcondition {
      condition     = contains([201, 204], self.status_code)
      error_message = tostring(self.response_body)
    }
  }
}
{% endhighlight %}

This token was then stored in Vault, just for shits and giggles:

{% highlight hcl %}
resource "vault_kv_secret_v2" "runner_registration_token" {
  for_each = data.http.runner_reg_token

  mount = "kv"
  name  = "github_runner/${each.key}"
  data_json = each.value.body
  custom_metadata {
    data = {
      created_by = "Terraform"
    }
  }
}

{% endhighlight %}

So that we could use it later when deploying the actual Noamd job:

{% highlight hcl %}
resource "nomad_job" "runner" {
  for_each = data.github_organization.selected
  jobspec = templatefile("github-runner.nomad.tpl", {
    registration_token = jsondecode(vault_kv_secret_v2.runner_registration_token[each.key].data_json).token,
    check_token        = jsondecode(data.vault_kv_secret_v2.name.data_json).runner_check,
    runner_version     = "2.310.2",
    org                = each.key
  })
}
{% endhighlight %}

The actual Nomad job template referred to here is a bit longer, so for the sake of brevity see [my Nomad jobs repo](https://github.com/brucellino/nomad-jobs/blob/v2.17.1/github-runner/github-runner.nomad.tpl).
Suffice to say that it has a pre-start which runs the `./configure.sh`  script with the data passed to it from Terraform (`registration_token`, `runner_version`, `org`) which configures the runner, then a main task which runs it, and eventually a post-stop task which removes the runner when the job is destroyed.

So far, so good.

But now it was time to confront two major issues which led me to a different approach:

1. The need for a runner to use a specific token for a specific repo in my personal account
1. Having runners on-demand

This would lead me to a re-architecture which I will discuss in a later post.

### The actual problem: Personal repo runners

Adding runners to a repo would mean generating a token _for each repo_ which I want to run CI with self-hosted runners on, and registering a runner with it.
The runner would have to be running persistently in order for actions requesting self-hosted runners to pick up jobs. Now, I currently have 167 repositories; sure, not all of them have the same level of activity, but if I wanted self-hosted runners for all of them, I would have to start 167 instances of the runner, each registered to the specific repo.

One alternative is to separate the repos into ones which use GitHub-hosted runners and ones which use self-hosted runners, say only private repos use self-hosted, whilst public repos use GitHub-hosted.
This wouldn't solve the problem necessarily, since some of the repos which consume the most time are public.

I could tag repos with a GitHub repo topic to decide which would be using self-hosted and then use that to pass as a query into the [GitHub repo](https://registry.terraform.io/providers/integrations/github/latest/docs/data-sources/repositories) lookup.
While this may in any case be a more elegant approach, I still only have ~ 20 slots in Hashi@Home[^slots].
I wouldn't be able to provide runners to all of the repos which need them.

### The actual problem: Scale to Zero

However, the bigger problem is that I would be wasting resources by reserving slots even if they are not being used.
The correct approach would be to scale to zero if we have no runs pending, and then create runners on-demand when runs are created by activity in GitHub.
That would be quite simple in principle -- GitHub already supports ephemeral runners, and the same job script as above, modified slightly would do fine.
I could use the [dispatch API](https://developer.hashicorp.com/nomad/api-docs/jobs#dispatch-job) to trigger a  [parametrized Nomad job](https://developer.hashicorp.com/nomad/docs/job-specification/parameterized), but

**that would mean being able to receive `POST`s on the Nomad API from GitHub**.

---

## A new adventure

This is where our hero met his first call to adventure[^heros].
Yes, I could find some way to expose my Nomad API to the internet, but I really didn't want to do that.
If there were some way that I could protect that endpoint to authenticate and allow only valid messages from GitHub, then I could build something which executed the right workflow to create runners on demand only when they are needed.

---

## Footnotes and References

[^runner_instructions]: I followed the instructions at [docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners#adding-a-self-hosted-runner-to-a-repository](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners#adding-a-self-hosted-runner-to-a-repository)
[^no_endpoint]: The only resource available in the Terraform provider for runners is creating a runner group, which as mentioned before was not available to me on the Free plan. Therefore, I had to make calls to the REST API to retrieve runner tokens.
[^slots]: There are on average 10 clients with around 2 CPU cores each. On average, because the computatoms are somewhat unreliable and need to be restarted periodically.
[^heros]: This is an ungainly reference to the moment in the [Hero's Journey](https://en.wikipedia.org/wiki/Hero%27s_journey) where the hero embarks on their exploration of the unknown.
