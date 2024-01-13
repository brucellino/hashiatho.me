---
layout: post
title: Terraform all the things
date: 2023-11-20 07:00 +0100
headline: Putting it all together - Terraforming Github runners on Nomad and Cloudflare.
categories:
  - blog
tags:
  - nomad
  - terraform
  - cloudflare
  - github
  - ci-cd
mermaid: true
---

## The problem

{% include diagrams/github-runners-cloudflare-diagram.html %}

The flow of data is easier to visualise perhaps as a sequence diagram:

<pre class='mermaid'>
---
title: Simplified event flow
sequence:
  actorFontSize: "128px"
  actorFontFamily: "IBM Plex Mono"
  messageFontSize: "128px"
  messageFontFamily: "IBM Plex Mono"
config:
  theme: base
  themeVariables:
    background: "#d8dee9"
    primaryColor: "#88c0d0"
    secondaryColor: "#81a1c1"
    tertiaryColor: "#ebcb8b"
    primaryTextColor: "#2e3440"
    secondaryTextColor: "#3b4252"
    primaryBorderColor: "#7C0000"
    lineColor: "#F8B229"
    fontSize: "28px"
    fontFamily: "IBM Plex Mono"
---
sequenceDiagram
  autonumber

  actor User

  box github
  participant GithubRepo
  participant GithubWebhook
  participant GithubAction
  participant GithubCIJob
  participant GithubRunner
  end

  box nomad
  %% participant NomadTunnelJob
  participant NomadDispatchAPI
  participant NomadRunnerJob
  end

  User->>GithubRepo: commit
  GithubRepo->>GithubWebhook: trigger webhook
  GithubWebhook->>NomadDispatchAPI: deliver payload
  GithubWebhook->>GithubAction: queue workflow
  GithubAction->>GithubCIJob: queue job
  NomadDispatchAPI->>NomadRunnerJob: start
  activate NomadRunnerJob
  NomadRunnerJob->>GithubRunner: create
  activate GithubAction
  loop Alive
    NomadRunnerJob->>GithubRunner: Report Health

    GithubRunner->>GithubCIJob: Notify presence
    GithubAction->>NomadRunnerJob: schedule job
    NomadRunnerJob->>NomadRunnerJob: Run job
    GithubCIJob-->>GithubAction: update status
    NomadRunnerJob->>GithubAction: Terminate

    end
  deactivate NomadRunnerJob
  NomadRunnerJob->>GithubRepo: Remove Runner
  GithubAction->>User: show status
  deactivate GithubAction
</pre>

As you you can see here, I've left out the crucial part of Cloudflare resources, assuming that the endpoint that we need to `POST` to is resolvable by Github.
Don't worry, it's just to save space and keep the diagram readable - I'll show in the next section exactly how Cloudflare fits into the picture.

Note however that there is a loop in the sequence while the runner is alive and processes a job.
Once the job finishes however, the loop exits and the runner is removed from the repository.

The runners are used once and destroyed.

## Terraforming

We will be creating all of these resources with Terraform.
Where should we start?
When I start out implementing something in Terraform, I usually start with declaring the providers:

{% highlight hcl %}
terraform {

  required_version = ">1.6.0" # modern terraform please...

  required_providers {
    # We need github to provide access to ... github. I know, it sounds crazy, but bear with me.
    # The Github provider will create the webhook resource, but is also used to look up data.
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }

    # Spoiler alert: we're going to need vault to read and write secrets
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }

    # Cloudflare will be used to create a few resources such as
    # the application, route, tunnel and worker
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.22.0"
    }

    # Spolier alert: turns out we will need the random provider too.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }

    # We'll be using the Nomad provider to register the job and perhaps other sundry resources.
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.1.0"
    }
  }
}
{% endhighlight %}

Ok, we've got the tools, now to go about creating the resources.

### Configuring providers

At the outset, the only thing we really have are the things that are already present in Github (my repositories and Github's own state), and a Cloudflare account with a registered domain.

We could go about looking up data from _e.g._ Github by writing a declaration like:

{% highlight hcl %}
# main.tf

variable "github_username" {
  description = "Username of the github user you want to instrument."
  default     = "brucellino"
  type        = string
}

## Get a list of all of my repositories
data "github_repositories" "mine" {
  query = "user:${var.github_username} archived:false"
}
{% endhighlight %}

Astute readers might object saying that only public repositories will be found like that, since we haven't provided any means to authenticate to GitHub, and seasoned Terraformers would then also ask things like "Where is the provider configuration?" and "Where is the backend configuration?"

Well, it turns out that I've actually written the terraform as a _module_, and thus ensured that the declaration is _abstract_.
The providers are configured in an _instantiation_ of the module:

{% highlight hcl %}
# instatiation main.tf

# We'll put the state in Consul, because hashify everything
terraform {
  backend "consul" {
    path = "terraform_github_nomad_webhooks/simple"
  }
}

# This is a module, so you can re-use it for your own domain,
# but I'm always going to be using mine so I set it as a default
variable "domain" {
  description = "The domain you will be deploying to. You must already own this domain."
  default     = "brucellino.dev"
  type        = string
}

# we're going to need some secrets, to configure the providers
# Again, since this is a module, we use a variable here.
# the KV secrets for hashi@home are to be found here
variable "secrets_mount" {
  type        = string
  description = "Name of the vault mount where the secrets are kept."
  default     = "hashiatho.me-v2"
}

# We don't need to pass anything to the vault provider, because we've set
# VAULT_ADDR and VAULT_TOKEN in the environment
provider "vault" {}

# Use vault to get the secrets for configuring the other providers
# The name of the secret should probably also be a variable, but we'll do that later
# For now, you have to have a secret in the mount called 'github' for the github token
data "vault_kv_secret_v2" "github" {
  mount = var.secrets_mount
  name  = "github"
}

# Use Vault to lookup the cloudflare secret containing the token used to
# authenticate the provider below
data "vault_kv_secret_v2" "cloudflare" {
  mount = "cloudflare"
  name  = var.domain
}

# Now we can configure the cloudflare provider with the token we've looked up in Vault
provider "cloudflare" {
  api_token = data.vault_kv_secret_v2.cloudflare.data.github_runner_token
}

# Ditto for github
provider "github" {
  token = data.vault_kv_secret_v2.github.data.gh_token
}

# We dn't need to pass anything to the Nomad provider, because we've set
# NOMAD_ADDR and NOMAD_TOKEN in the environment
provider "nomad" {}
{% endhighlight %}

Several configuration parameters are not shown here, such as the Nomad and Vault tokens, because I usually already have them set in the environment[^NomadVaultSecret].
Now that the providers are configured, we can go about creating all of the resources we need.

### The rest of the damn owl

You know what I really don't like?
Those "tutorials"  that start off really explicit and simple, you follow them nodding your head going  "yeah, ok, I get it, I can do this"  and then somewhere around step 3 it pulls a magic trick with a wave of the hand and out pops a fully-formed masterpiece that you have no idea how to make.
That's not what I'm trying to do here, so let's take a step back and try to reason about the [rest of the damn owl](https://www.reddit.com/r/restofthefuckingowl/)[^Rest-of-the-damn-owl].

#### Github

Naively, we might assume that the first thing to do is **register the webhook**, but the first thing that the webhook will ask you when creating it is "where should I POST the event payload to"?
So, we'll need the **domain** and **route** first.
Once we have that, we can register the **webhook**.
When a [webhook is registered](https://docs.github.com/en/rest/repos/webhooks?apiVersion=2022-11-28#create-a-repository-webhook), a **webhook secret** can be declared which the receiving end should also have.
This secret is used to sign the hash of the payload that is sent by Github, and then by the receiving end to validate the payload, providing a means for ensuring message authenticity[^mac].

So, in github we'll need:

1. A webhook with
   1. webhook secret
   2. endpoint

We'll also need to look up:

1. Specific repositories
2. Github ip ranges

{% highlight hcl %}
# main.tf

# Get a list of all of my repositories
data "github_repositories" "mine" {
  query = "user:${var.github_username} archived:false"
}
# We will use these IP ranges to tune our ZTA later
data "github_ip_ranges" "theirs" {}

# Use the random provider to generate a random phrase
# to use as the webhook secret
resource "random_pet" "github_secret" {
  length    = 3
  prefix    = "hashi"
  separator = "_"
  keepers = {
    "repo" = data.github_repositories.mine.id
  }
}

# Register the webhook on all repos in the data lookup.
# We refer here to a worker domain which is present elsewhere in the definition
resource "github_repository_webhook" "cf" {
  for_each   = toset(data.github_repositories.mine.names)
  repository = each.value
  configuration {
    url          = "https://${cloudflare_worker_domain.handle_webhooks.hostname}"
    content_type = "json"
    insecure_ssl = false
    secret       = random_pet.github_secret.id
  }

  active = true
  events = ["workflow_run", "pull_request", "workflow_job"]
}
{% endhighlight %}

#### Cloudflare

The Cloudflare edge servers will be able to receive that data, but the response will be a 500 at best, because there's nothing to serve the request.
So the next thing we'll need is to attach a **worker** to the route to be able to respond when webhook payloads hit the URL[^cidr_filter].
This would tell Github that "ok, we've received your webhook, thank you. Carry on", but we'd still have to invoke the actual runner if required by the specific event.

The worker script will deal with the business logic, including the authentication of the payload data based on a secret shared between Github and Cloudflare used to sign it mentioned above.
If all goes well, the script will be responsible for sending a dispatch POST to the Nomad API.
Recall that the Nomad API is running in my local private network, so we need to **create a tunnel** for it, with an **application** to expose it to the Cloudflare edge.
This application will be able to receive and respond to requests _specifically_ for Nomad, so I don't want to expose it to anything, but _only_ to the cloudflare worker which deals with incoming Github webhooks.
This is a machine-machine interaction, so the authentication mechanism will be with a **service token**.
We can then make an **access rule** which only allows requests which have that token in their headers.

So in cloudflare we'll need:

1. A worker with:
   1. secrets bindings
   2. a worker domain
3. A Cloudflare access application with
   1. An Access Group
   2. An Access Policy
4. A Cloudflare Tunnel with
   1. a tunnel configuration
5. (optional KV namespace for metadata and job tracking)

We'll also need to look up:

1. Accounts
2. Domains
3. Cloudflare Tunnel Secrets[^not-quite-terraformable]

{% highlight hcl %}
# main.tf
# Get the cloudflare accounts from the token we've used to configure the provider
data "cloudflare_accounts" "mine" {}

# Look up the zone we'll be creating the worker route on
data "cloudflare_zone" "webhook_listener" {
  name = var.cloudflare_domain
}

# Use the Cloudflare KV store to keep metadata about Github.
# Can be used later in the script to check incoming payloads.
# First create the namespace
resource "cloudflare_workers_kv_namespace" "github" {
  account_id = data.cloudflare_accounts.mine.accounts[0].id
  title      = "${var.github_username}_github_runner"
}

# We'll put the github webhook secret in cloudflare KV so that we can
resource "cloudflare_workers_kv" "github_webhook_secret" {
  account_id   = data.cloudflare_accounts.mine.accounts[0].id
  namespace_id = cloudflare_workers_kv_namespace.github.id
  key          = "github_webhook_secret"
  value        = random_pet.github_secret.id
}

# The webhook IPs is the list of CIDRs that Github webhooks are sent from
resource "cloudflare_workers_kv" "webhook_ips" {
  account_id   = data.cloudflare_accounts.mine.accounts[0].id
  namespace_id = cloudflare_workers_kv_namespace.github.id
  key          = "github_webhook_cidrs"
  value        = jsonencode(data.github_ip_ranges.theirs.hooks_ipv4)
}

# The actions IPs is the list of CIDRs that Github actions communicate on
resource "cloudflare_workers_kv" "actions_ips" {
  account_id   = data.cloudflare_accounts.mine.accounts[0].id
  namespace_id = cloudflare_workers_kv_namespace.github.id
  key          = "github_actions_cidrs"
  value        = jsonencode(data.github_ip_ranges.theirs.actions_ipv4)
}

# The actual worker script which the worker executes
# It will need the Nomad access token and Cloudflare access credentials
# in order to POST to the tunnel.
resource "cloudflare_worker_script" "handle_webhooks" {
  account_id = data.cloudflare_accounts.mine.accounts[0].id
  name       = "github_handle_incoming_webhooks_${var.github_username}"
  content    = file("${path.module}/scripts/handle_incoming_webhooks.js")
  kv_namespace_binding {
    name         = "WORKERS"
    namespace_id = cloudflare_workers_kv_namespace.github.id
  }

  secret_text_binding {
    name = "CF_ACCESS_CLIENT_ID"
    text = data.vault_kv_secret_v2.service_token.data.cf_access_client_id
  }

  secret_text_binding {
    name = "CF_ACCESS_CLIENT_SECRET"
    text = data.vault_kv_secret_v2.service_token.data.cf_access_client_secret
  }

  # Add nomad acl token to secret
  secret_text_binding {
    name = "NOMAD_ACL_TOKEN"
    text = data.vault_kv_secret_v2.service_token.data.nomad_acl_token
  }
  module = true
}

# Expose the worker on a domain
resource "cloudflare_worker_domain" "handle_webhooks" {
  account_id = data.cloudflare_accounts.mine.accounts[0].id
  hostname   = "github_webhook.${var.cloudflare_domain}"
  service    = cloudflare_worker_script.handle_webhooks.name
  zone_id    = data.cloudflare_zone.webhook_listener.zone_id
}

# Create the access application.
# Some of these values need to be parametrized, but I'm serving on the
# domains I own, as seen here.
resource "cloudflare_access_application" "nomad" {
  account_id          = data.cloudflare_accounts.mine.accounts[0].id
  name                = "nomad"
  custom_deny_url     = "https://hashiatho.me"
  type                = "self_hosted"
  domain              = "nomad.brucellino.dev"
  self_hosted_domains = ["nomad.hashiatho.me", "nomad.brucellino.dev"]
}

# RBAC access group defining who can access the application
# This requires a valid service token.
resource "cloudflare_access_group" "nomad" {
  account_id = data.cloudflare_accounts.mine.accounts[0].id
  name       = "github-webhook-worker"
  include {
    any_valid_service_token = true
  }

  require {
    any_valid_service_token = true
  }
}

# The policy for adding identities to the group we defined above
# This one requires a valid service token, and includes the specific token
# which we have created.
# I cheated here, the token is created out-of-band because $reasons
resource "cloudflare_access_policy" "service" {
  name           = "ServiceWorker"
  application_id = cloudflare_access_application.nomad.id
  decision       = "non_identity"
  precedence     = "1"
  account_id     = data.cloudflare_accounts.mine.accounts[0].id
  require {
    any_valid_service_token = true
  }
  include {
    service_token = ["fcbd819b-771c-4e0b-a22e-d38e8361d2e8"]
    group         = [cloudflare_access_group.nomad.id]
  }
}

# This is the ID which will be used by the tunnel running locally
# to connect to the Cloudflare Edge
resource "random_id" "tunnel_secret" {
  keepers = {
    service = cloudflare_access_application.nomad.id
  }
  byte_length = 32
}

# Create tunnel connected to the application route,
# using the shared secret defined above.
resource "cloudflare_tunnel" "nomad" {
  name       = "nomad"
  account_id = data.cloudflare_accounts.mine.accounts[0].id
  secret     = random_id.tunnel_secret.b64_std
  config_src = "cloudflare"
}

# Final tunnel configuration connecting ingress rules
# This routes incoming requests to the ingress hostname
# to the backend service.
# I should be able to call nomad.service.consul here, but for now it's a dirty hack
# where I'm hardcoding one of the known Nomad servers. Sue me.
resource "cloudflare_tunnel_config" "nomad" {
  account_id = data.cloudflare_accounts.mine.accounts[0].id
  tunnel_id  = cloudflare_tunnel.nomad.id
  config {
    ingress_rule {
      hostname = "nomad.${var.cloudflare_domain}"
      path     = "/"
      service  = "http://bare:4646"
    }
    ingress_rule {
      service = "http://bare:4646"
    }
  }
}
{% endhighlight %}

#### Nomad

At last we can hit the Nomad API.
We'll be using the [Nomad parametrized job](https://developer.hashicorp.com/nomad/docs/job-specification/parameterized) type, so that we can invoke ephemeral runner instances, without having to register persistent runners in repositories.
This is a key aspect which allows us to scale as needed, and have zero capacity when not needed, saving resources and money.

We will therefore need a **Nomad job** both for the tunnel mentioned above, as well as for the Github runner parametrized job.

So, for Nomad we will need:

1. Nomad service job for `cloudflared` tunnel
2. Nomad parametrized job for Github runner

{% highlight hcl %}
# Add the Nomad job for cloudflare
resource "nomad_job" "cloudflared" {
  jobspec = templatefile("${path.module}/jobspec/tunnel-job.hcl", {
    token = cloudflare_tunnel.nomad.tunnel_token
  })
}

# Add dispatch batch job for workload
resource "nomad_job" "runner_dispatch" {
  jobspec = templatefile("${path.module}/jobspec/runner-dispatch.hcl.tmpl", {
    job_name       = "github-runner-on-demand",
    runner_version = var.runner_version,
    # runner_label   = "hah,self-hosted,hashi-at-home",
    # check_token = data.vault_kv_secret_v2.github_pat.data.token
  })
}
{% endhighlight %}

Finally, we have all of the resources necessary and we can Terraform all the things!.

For all of the code, see [the repo](https://github.com/brucellino/terraform-github-nomad-webhooks)

## Discussion

I've shown here a few of the gritty details of how to build this with Terraform.

There are a few rough edges still, some hardcoded information and a few resources which were created by hand, and not terraformed.
From what I've read on the various fora, I believe these will be implemented soon in their respective providers.

I haven't gone into detail regarding the worker itself or the Nomad job definition here - you can find them in [the repo](https://github.com/brucellino/terraform-github-nomad-webhooks).
I hope to discuss them in a future post.

I've tried very hard here to provide a linear description of how to go about building this.
The actual experience was quite different to this - I spent a lot of time experimenting with Cloudflare resources before I got it right.
I'm probably just slow, and once I finally got it properly implemented, it all made sense.
The hardest part was the actual worker, but that's just because I suck at writing Javascript... hey, I'm getting there.

I've used Hashi at Home services (Vault, Nomad and Consul) and a free Cloudflare account to do this, and honestly it's really nice to be able to run as many runners and CI actions as I want free of charge, by using hardware that I've already paid for.
The only cost involved here was my fixed-line subscription and the computatoms I've got in the cluster.
Running these in Github itself, I'd probably need the Enterprise subscription, since the Team subscription only gives me [1000 CI/CD minutes a month over the free account](https://github.com/pricing#compare-features).
It's neither here nor there whether I would actually save money[^tco], but it certainly works.
What is more, by implementing this solution, I've learned a lot about how Github runners actually work, some details of Nomad and Cloudflare, not to mention the Javascript I needed to know to write the worker.

### Moral of the story

Making things yourself is important, you cannot learn if you don't do.
And sometimes owning your own things is better than subscribing to other peoples' things.

## References and footnotes

[^NomadVaultSecret]: I actually want a short-lived token from for Nomad from the Vault Nomad secrets mount, but I haven't gotten that to work yet. I also want some form of short-lived token for Vault, but full-disclosure, I'm using a root token at home 😱.
[^rest-of-the-damn-owl]: I'm referring to the things that the ["How to draw an owl"](https://knowyourmeme.com/memes/how-to-draw-an-owl) meme refers to.
[^cidr_filter]: It would be best to expose the worker _only_ to known Github Actions endpoints. Github actually [does expose their IP ranges](https://docs.github.com/en/rest/meta/meta?apiVersion=2022-11-28#get-github-meta-information) and the provider [implements a `data` source for it](https://registry.terraform.io/providers/integrations/github/latest/docs/data-sources/ip_ranges). However Cloudflare access rules [can only be specified as /16 or /24 at the moment](https://community.cloudflare.com/t/ip-access-rule-api-error-cidr-range-firewallaccessrules-api-validation-error-invalid-ip-provided/399939) which means having to convert the /23 and other CIDRs that Github returns to expand to those sizes. Honestly, it felt like I'd have to do a hack and I leave that for next time.
[^mac]: This is a crucial part of security of the setup -- without it, I could send any old data through the worker and do very malicious things to my Nomad cluster. I followed the [official guide](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries#validating-webhook-deliveries) to implement the function in [Javascript](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries#javascript-example) when implementing the worker.
[^not-quite-terraformable]: This resource is not quite terraformable yet.
[^tco]: For example, most of the runners run on a 4 CPU, 32 GB RAM Lenovo Thinkcentre I got refurbished for about 100 euros. That's just over 2 years of a team membership... but I can use the machine to do lots of other things as well, which I can't really do with the Github actions. Owning things is actually pretty rad.
