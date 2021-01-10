---
layout: page
title: Playbook
permalink: /playbook/
---

# Hashi@Home playbook

This describes the "Playbook" for getting Hashi on _your_ home.
It is an attempt to describe the sequential steps.
This is very hard to do accurately, so your mileage may vary.
Hell, _my_ mileage may vary, but the idea is to have a good conceptual model from start to finish.

There are several moving parts, and the path is not linear.
Getting these things working together presents several forks in the road, so this shouldn't be considered a prescriptive guide.

1. **Bootstrap**
   1. Boot the hardware<br><small>Create SD cards and configure the computatoms to join your home network and generate an Ansible inventory.</small>
   1. Prepare nodes<br><small>Using a "base" Ansible role, apply a common base configuration to the computatoms</small>
   1. Bootstrap platform <br>
      <small>Using Ansible playbooks, deploy the initial bootstrap of the Hashi stack</small>
      1. Deploy Consul
      1. Deploy Vault
      1. Deploy Nomad
1. **Terraform** <br>
   <small>Using the Consul service as a backend, Terraform the services (ACLs and other resources)</small>
   1. Terraform Consul
   1. Terraform Vault
   1. Terraform Nomad
1. **Deploy**
   1. Deploy Waypoint
   1. Integrate Waypoint with Nomad
   1. Declare Nomad workloads
   1. Deploy workloads to Nomad clients
1. **Maintain** <br><small>Now that the platform is up, continuously improve it and send changes through the delivery pipeline</small>
