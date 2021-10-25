---
layout: post
title: Terraform Day 1
date: 2021-01-10 08:51 +0100
headline: What my hand hath wrought let no hand undo
categories:
  - blog
tags:
  - terraform
  - consul
  - ansible
---

## Day 1

The hardware is booted and has a network address, you've deployed the first basic layer of the platform, Consul. **Now what?**

In our first steps, we were concerned with _bootstrapping_ the basic OS and the lower-lying parts of the network stack.
The first step was to apply a common configuration across the computatoms, which was done with a few Ansible roles.
This part of the deployment can be considered as applying _layers_ to infrastructgure, or to use the Ansible jargon _roles_ to computatoms.
The term layer implies that there is some hierarchy to them, which is not strictly the case.
Indeed, I found one of the conceptually diffuclt aspects of this project initially was to have a clear idea of the dependency graph of infrastructure components.

Which should go first? Consul? Nomad? Vault?
When do I write an Ansible role and when do I start Terraforming?

Consider for example that Consul needs a gossip key, as does Nomad -- should these be read from Vault? This means Vault comes first.
But Vault can be deployed with Nomad, and registered as a service with Consul. Doesn't that mean that Consul comes first?

Until I realised that the deployment can be _eventually consistent_, this seemingly circular dependency grated my mind.
In fact, the thinking and grating around this resulted in my rudimentary [playbook]({{ site_url }}/playbook).

## What can we form, with Terraform

In order to decide where to start in describing the Hashi@home infrastructure as code, I found it useful to take a tour of the [Terraform registry](https://registry.terraform.io).
Glancing over the resources and data sources of the [Consul](https://registry.terraform.io/providers/hashicorp/consul), one might be tempted to go ahead and terraform Consul services, nodes, _etc_.
However, this isn't possible without the work of deploying Consul to the nodes themselves fist.
Since there is no IaaS layer in this project, but we are running on bare-metal, the infrastructure layers need to be provisioned using something that can be accessed at the underlying OS level.
So, terraform in our case will be acting on layers of infrastructure _above_ Consul.

In order to get to the level where we _have_ something to terraform, we need to start deploying some services, with Nomad.
When these services are eventually deployed, we will have an API surface area for Terraform to interact with to converge the state of the services.

More about that in the [the next chapter]({% post_url 2021-02-01-nomad-day-2 %}).
