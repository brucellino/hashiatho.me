---
layout: post
title: A new playbook
date: 2022-12-27 07:00 +0100
headline: Looping back around again
categories:
  - blog
tags:
  - consul
  - vault
  - ansible
---

It's three years since I started this silly little side project to use Hashicorp's products at home.
The goal has morphed slightly over the years, from a mere curiosity to helping me have a better understanding of what it really means to create zero-trust cloud-native environments.

I started, naturally, from what I already knew, using tooling which I was very comfortable with to create environments from scratch, in order to then further explore.
Since my experience up to 2019 was _either_ with entirely dynamic cloud environments _or_ more static bare-metal environments, I didn't quite realise how Hashi tools _really_ worked to build ***cloud-native environments***.

The initial approach was **teleological**, with a specific starting and ending point in mind.
The designer in me took a back seat to the engineer, which set to work connecting the dots from start to finish as if there were a single path to tread.

But what if we _design instead of build_?

## Less cowbell

What does it mean to design instead of build?
The first thing that comes to mind is that instead of a controller taking actions against a set of targets, a set of rules governing the behaviour of components is adoapted.
Instead of starting with prescriptive, directed series of tasks, we define actions that are taken based on rules, react to events and use data to let components understand what needs to be done.
This can help in reducing the complexity of configuration management, making each action smaller and more comprehensible, while also allowing a greater level of automation.

In a very roundabout way, I'm calling this the "Less Cowbell[^cows]" approach for now.
Essentially, this can be interpreted as relying less on a central point of control for configuration, with less reliance on fully-formed configuration components (_i.e._ Ansible roles).
It could possibly be thought of as "Configuration as Data"[^Kelsey_s_tweet], with relevant rules.

I've gone to some length to write Ansible roles as self-sufficient, flexible components which can be used in a variety of situations, but they still require a fixed set of playbooks to invoke them, not to mention an Ansible controller to run the playbook from.

Even basic concepts like the Ansible inventory required knowledge of the system which I do not want to assume.
Consider the difference between the two scenarios:

1. Configure all consul servers as servers, then configure all consul clients as clients
1. Configure all consul servers as servers, then every configure every other machine according to it's declared role

In the first case, we need to know which machines fall into which groups

## Data Bedrock and Catch-22

The original playbook started from the Consul layer, which made sense initially in a naive way, because with a service discovery layer, we could start to deploy other services like Vault and Nomad.
However, I soon came up against what seemed like a Catch-22:

> In order to deploy Vault in HA, we need Consul.
> In order to secure Consul, we need Vault.

There are plenty of ways to break this Catch-22 -- I initially chose to deploy Consul insecurely (no TLS), for example.
In general, there are cloud services which break the symmetry, meaning that we can presume the existence of an external key store, certificate authority _etc_ which can be used to stand on when initially bootstrapping the cluster.
In my case there are no such cloud services, by choice, so I am forced to make a decision on which service is more "fundamental" than the other -- did the chicken come first, or the egg?

In my case, I chose Vault as the bedrock. This means that I assume the availability **and knowledge** of a Vault service which can be used as a source of data to configure.

This is a design decision, and made self-consciously knowing how I want computatoms to behave when they join the cluster.

## More intentional Vault

I originally held the opinion that the base images should be as simple as possible, with zero assumptions.
Without a means to authenticate themselves, computatoms need some external driver to be able to request secrets from Vault in order to configure Consul, meaning a _deus ex machina_ in the form of a person with access to Vault running a playbook.
Shouldn't they be able to introduce themselves to the cluster without my help?
Computatoms should authenticate to Vault using the [AppRole](https://developer.hashicorp.com/vault/docs/auth/approle) method, with a role ID delivered to them as part of the initial configuration.
Taking things a bit further, we could request that agents not only authenticate themselves to the Vault instance, but also request the secrets that they will eventually need themselves, using the [Vault Agent](https://developer.hashicorp.com/vault/docs/agent/autoauth/methods/approle) templating functionality to [write files](https://developer.hashicorp.com/vault/docs/agent/autoauth/sinks/file) such as PKI certificates and keys.

This approach means making the conscious choice to _first_ deploy Vault and then use it explicitly as a dependency to the other layers.
Whilst this does remove a degree of freedom from our system, it also gives us a few things which we can assume about the system when we introduce ourselves to it.

## Better use of Consul

Now that we can assume the presence of Vault, can we do something more with Consul?

The original approach was to assume nothing about our computatoms, and arbitrarily assign them roles (server or agent) on the fly.
However, in the real world this doesn't really serve my purposes.
There are significant differences between individual computatoms which make some of them more reliable than others, so it make more sense to assign specific roles to specific machines.

In a cloudier environment (where, say all instances in a pool have the same hardware configuration), the assume-nothing fully dynamic approach would make sense, and I still want to try that sometime.

✌ Written by Bruce, not AI
