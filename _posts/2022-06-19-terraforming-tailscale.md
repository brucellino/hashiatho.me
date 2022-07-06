---
layout: post
title: Terraforming Tailscale
date: 2022-06-19 12:00 +0100
headline: Securely accessing computatoms from anywhere
categories:
  - blog
tags:
  - vault
  - terraform
  - consul
  - ansible
---

This is a story about how I finally realised what Tailscale was for.

## The mother of re-use

I have often come to need to access the services at Hashi@Home from somewhere that is ... not home.
The most common case is retrieving secrets (passwords or tokens) for websites I'm browsing on my phone, or while on a mission somewhere.

Another example is during continuous integration pipeline execution.
It's availability and ease of use makes [Github Actions](https://github.com/features/actions) an attractive first port of call for creating continuous integration workflows, but since the runners which execute the steps in the workflow are hosted in Azure by default, they do not have access to the services at home.

The Consul and Vault services in Hashi@home are the most widely used, since they are used to provide most of the configuration and sensitive data to all the Nomad jobs, _etc_.
Github runners, however are unable to use them to discover services or access credentials.
One alternative would be to add these secrets to [Github Actions secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets), but seems an inelegant repetition of data, which nevertheless doesn't provide the functionality needed.
The Terraform AWS provider for example cannot uses this when creating short-lived IAM users for executing plans.

The other alternative of hosting [Github Actions runners in Hashi@Home](https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners) also does not seem all that attractive.
Besides the resource consumption of my precious computatoms, I would have the overhead of having to maintain my own CI when a perfectly good one already exists in the cloud.

The nuclear option of exposing Hashi@Home to the internet was considered for a brief feverish moment of desperation ... until I remembered Tailscale!

## If only I had a VPN

What I really wanted was a VPN that I could add Hashi@Home to, and then selectively add GitHub runners when necessary.

Enter [Tailscale](https://tailscale.com).

> A secure network that just works

Tailscale is a VPN based on Wireguard that provides a central point of control via [their own magic](https://tailscale.com/blog/how-tailscale-works/).
Install an agent on a machine, authenticate to the co-ordination server of your tailnet and voila, you're in a VPN.

If I could add all my computatoms to the Github tailnet (the network created when authenticating with the Github identity provider), then I could also do so for the Github runner when it executes.
In hindsight, I should have kicked myself for having spent so long agonising over this dilemma, because [Tailscale themselves had published the idea over a year ago](https://tailscale.com/blog/2021-05-github-actions-and-tailscale/).

## Terraforming Tailscale

Now the somewhat tricky part -- how to add the computatoms to the tailnet declaratively?

My first instinct was to write an Ansible playbook to add the packages to the OS and start the service, but how would I manage the authentication keys?

> Terraform the sucker

My computeatoms are all in the Consul catalog.
I would use that as an inventory and generate a Tailscale tailnet key for each of them.
The key would be stored in a Vault KV store, where I could happily rotate them and retrieve them later.

Using the Tailscale, Vault and Consul providers this would be a cinch:

{% highlight hcl %}

terraform {
  required_providers {
    tailscale = {
      source  = "davidsbond/tailscale"
      version = "0.11.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "3.7.0"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "2.15.1"
    }
  }
  backend "consul" {
    path = "hashiatho.me/tailscale"
  }
}
{% endhighlight %}

The state for this definition would be stored in Consul KV.

In order to create Tailscale resources, we need an API token.
Guess where that's stored...

{% highlight hcl %}
data "vault_generic_secret" "tailscale" {
  path = "hashiatho.me/tailscale"
}
{% endhighlight %}

With the Tailscale API token, we can configure the Tailscale provider

{% highlight hcl %}
provider "tailscale" {
  api_key = data.vault_generic_secret.tailscale.data.tailscale_secret_key
  tailnet = data.vault_generic_secret.tailscale.data.tailnet
}
{% endhighlight %}

We want a different Tailnet key for each computeatom.
In order to do this, we will need to have a `for_each` of some data structure, but first we need to actually get the data.
Using the Consul cataglo, we get the nodes in the desired datacenter[^lol]:

{% highlight hcl %}
data "consul_nodes" "nodes" {
  query_options {
    datacenter = var.datacenter
  }
}
{% endhighlight %}

Now we have the data we need to configure the Tailscale provider and we know all the nodes in the Consul catalog, so we can proceed to create the tailnet key for each of them:

{% highlight hcl %}
resource "tailscale_tailnet_key" "node_key" {
  for_each      = toset(data.consul_nodes.nodes.nodes[*].name)
  reusable      = true
  ephemeral     = true
  preauthorized = true
}
{% endhighlight %}

As seen, we loop over the set of node names in the Consul catalog so that we can retrieve the keys later by node name.
In preparation for that, though, we put the generated keys somewhere safe, _i.e._ a Vault KV store:

{% highlight hcl %}
resource "vault_kv_secret_v2" "tailscale" {
  mount = "hashiatho.me-v2"
  name  = "tailscale_access_keys"

  data_json = jsonencode(
    {
      for k in keys(tailscale_tailnet_key.node_key) : k => tailscale_tailnet_key.node_key[k].key
    }
  )
}
{% endhighlight %}

### Securely provisioning the keys

You may be asking yourself why we are adding the generated keys to a Vault KV store when they are literally right there in the Terraform state!

This is because I want to use Terraform to manage the state of the tailnet itself, but I don't want to give arbitrary entities access to the Terraform state (which also contains our Tailscale API keys!).

I want to create a separation of concerns between the entity which manages the state and the entity which configures the consumers of that state, so that the former can perform create/update/delete operations, but the latter can only read the tailnet key for itself.

Admittedly, this involves a bit of Consul ACL and Vault policy magic which I have not yet implemented, but left as an exercise to the SRE in me.
The separation is there for the purposes of this demonstration, but without securing access to the state backend, it would be remiss of me not to emphasises that **all of the secrets used in the Terraform statement are exposed**.
There, I said it.

## Adding nodes to the network

Now that we have distinct tailnet keys for each of the computeatoms in our Tailnet, we can go about configuring them and adding them to the network.

I alluded to the fact that we would do this with an Ansible playbook.
In fact, I decided to add in the Anisble role for the base configuration of the computeatoms.
In principle this role should be applied to every node which enters the catalog, and every a new version of the role is released, but in practice I run it manually when the urge overcomes me[^or].

The following tasks were added to `tasks/tailscale.yml`, following the [Tailscale installation guide](https://tailscale.com/kb/1031/install-linux/):

{% highlight yaml %}
{% raw %}
---

# Tasks for tailscale

- name: Add tailscale gpg key
  become: true
  ansible.builtin.apt_key:
    url: "{{ tailscale_pkgs_url }}/{{ ansible_lsb.codename }}.noarmor.gpg"
    state: present
    validate_certs: true

- name: Add tailscale packages repo
  become: true
  ansible.builtin.apt_repository:
    repo: "deb {{ tailscale_pkgs_url }} {{ ansible_lsb.codename }} main"
    state: present
    mode: 0644
    update_cache: true
    validate_certs: true
    filename: tailscale

- name: Ensure tailscale package
  become: true
  ansible.builtin.package:
    name: tailscale
    state: present
{% endraw %}
{% endhighlight %}

The `tailscale_pkgs_url` variable is stored in the defaults for the role and points to their repository.
Next we retrieve the Tailscale keys for the computatoms

{% highlight yaml %}
{% raw %}

- name: Get tailscale keys from vault
  delegate_to: localhost
  run_once: true
  ansible.builtin.set_fact:
    tailscale_keys: "{{ lookup(
      'community.hashi_vault.vault_kv2_get',
      'tailscale_access_keys',
      engine_mount_point='hashiatho.me-v2')}}" # noqa line-length
{% endraw %}
{% endhighlight %}

and finally use them to start Tailscale:

{% highlight yaml %}
{% raw %}

# Use the vault key lookup to start tailscale with it's auth key

- name: Start tailscale
  ansible.builtin.command:
    cmd: "tailscale up --auth-key {{ tailscale_keys.data.data[ansible_hostname] }}"
  register: tailscale_up
  changed_when: false
{% endraw %}
{% endhighlight %}

## Github Runner Catch 22

Now, I can use the Tailscale Github Action to add the Github runner to my tailnet, _and access the services in Hashi@Home_!
Since the Tailnet sets up a DNS, I can set things like `CONSUL_HTTP_ADDR=<computeatom>.brucellino.github.beta.tailscale.net:8500`, where `computeatom` is the name of one of the computeatoms in the datacenter.

There is, however a Catch 22.
In order to add the runner to the tailnet, I need access to a secret, which is in the Vault, which is only accessible via the Tailnet, which I can only access if I have access to the secret.

The easiest way to get out of this catch is to [Terraform a Github Actions secret](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) pre-emptively into the repos that we want to have access to our VPN.

{% highlight hcl %}
resource "github_actions_secret" "tailnet_auth_key" {
  repository       = data.github_repository.selected.repo_id
  secret_name      = "TS_KEY"  #pragma: allowlist secret
  plaintext_value  = data.vault_generic_secret.tailnet.github_key
}

{% endhighlight %}
Doing so will allow us to join our Github Actions runners to the tailnet and be allowed into the sweet, sweet embrace of Hashi@Home:

{% highlight yaml %}
{% raw %}

# .github/workflows/main.yml

steps:
.
.
.

- name: Join Tailnet
    run: sudo tailscale up  --authkey ${{ secrets.TS_KEY }}
{% endraw %}
{% endhighlight %}

## Wrapping it up

And there we have it -- our Github Actions can now access Hashi@Home services like Vault and Consul, as well as other services running on Nomad registered in the Consul catalog using an ephemeral Tailscale key.

There is much to improve on.

The security posture of this setup is not great since secrets are being leaked to actors which they should not be.
We've already referred to the fact that the state stored in Consul contains all of the sensitive data, so that needs to be locked down with an appropriate ACL.

Another example is the retrieval of the tailnet auth keys by the Ansible task -- it currently reads the entire value of the Vault key into memory, including the all of the values for all computatoms.

This doesn't seem right, the atom and only the atom should have access to its secrets.

In order to reduce this risk, I would like to have a vault policy which allows only fields matching the requestor hostname to be accessed.

Nontheless, terraforming Tailscale to add Hashi@Home computatoms allows me to flip a switch on my laptop or phone and access internal services from pretty much anywhere in safe and secure way.

Given that I wrote two files to make this happen, it's hard to express just how magical it feels. Basically cheat codes for the internet!

---

[^lol]: lol, "datacenter" still cracks me up.
[^or]: Or, as in this case, there is a new feature added
