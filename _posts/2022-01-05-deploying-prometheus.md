---
layout: post
title: Deploying Prometheus
date: 2022-01-05 12:00 +0100
headline:
categories:
  - blog
tags:
  - monitoring
  - prometheus
  - cncf
  - consul
  - vault
  - nomad
---

# Monitoring gameplan

Now that I have selected a toolkit for monitoring, it's time to plan the deployment.

As a rough outline, it will go as follows:

1. Ensure that data providers (prometheus exporters) are present and delivering data
1. Plan a configuration of prometheus that will discover and scrape these endpoints
1. Deploy prometheus and validate that data is being scraped

## A strange loop

> In order to monitor Nomad, we need to deploy prometheus... on Nomad.

This statement of the monitoring gameplan sounds like a Catch-22.

Before we begin, it warrants a moment to consider which level of Hashi@Home the prometheus service will be deployed at.
We have essentially two options:

- as a native service on one of the computatoms
- as a Nomad job scheduled across the cluster

In the former case, we have a service which is independent of the higher software layers, and can therefore monitor them.
If, for example the Nomad service loses quorum, the prometheus service will probably die and we will lose all monitoring.
Deploying prometheus as a service directly on the OS of one of the computatoms, we can ensure that, while that computatom is up, we will be able to scrape metrics and alert on events.
However, if anything should happen to the computatom which prometheus is running on, we will equally have a complete outage of the service.
So, how do we ensure that prometheus itself is appropriately available?

[_"Quis custodiet ipsos custodes?"_](https://en.wikipedia.org/wiki/Quis_custodiet_ipsos_custodes%3F) is a recursive problem.

I think of it as a ["Strange Loop"](https://en.wikipedia.org/wiki/Strange_loop):

> A strange loop is a cyclic structure that goes through several levels in a hierarchical system. It arises when, by moving only upwards or downwards through the system, one finds oneself back where one started. Strange loops may involve self-reference and paradox.

In our case, the place where we start, which is also the place where we want to end, is a system which is capable of monitoring itself.

The loop's hierarchy goes a little like this:

1. We have a system capable of monitoring itself
1. the system discovers that it is not yet monitoring itself
1. The system adds a layer capable of executing jobs
1. A job is defined for monitoring a system
1. The system deploys the monitoring job
1. We have a system which capable of monitoring itself

In the first execution of this cycle, I am part of the system, but by the time we get to the end of the cycle, I am no longer needed, the system is self-sufficient.

## Deploying Prometheus

To put it in more practical terms, I plan the following steps:

1. Deploy base image, including prometheus node exporter
1. Deploy Consul layer
1. Deploy Nomad layer
1. Deploy Prometheus job in Nomad

We have a few benefits, compared to the single-node static deployment option.
First of all, we can take advantage of the various reliability features in Nomad to ensure that the service is available.
We can [force restarts](https://www.nomadproject.io/docs/job-specification/check_restart) based on health checks, [migrate](https://www.nomadproject.io/docs/job-specification/migrate) the service to a new node if the on it's running on fails, or [reschedule](https://www.nomadproject.io/docs/job-specification/reschedule) the service if the job fails, _etc_.

This is taking advantage of the platform to provide higher functions in the platform itself.

## What to monitor -- prometheus configuration

Prometheus exposes data via the exporters
We can enable the simplest of exporters, the [node exporter](https://github.com/prometheus/node_exporter), and start scraping that.
Then, we

### Hashi At Home stack

Since we can assume that we are deploying prometheus into an _existing_ Consul cluster via Nomad, and that there is a Vault service running aside these, we have already a list of things we want to monitor.

Hashicorp products provide good built-in telemetry options:

- Vault telemetry is [configurable](https://www.vaultproject.io/docs/configuration/telemetry) via a server stanza. However, in order to monitor Vault we need a token which can be used to access the metrics endpoint.
- Consul
- Nomad has a very [comprehensive monitoring guide](https://www.nomadproject.io/docs/operations/monitoring-nomad) which includes suggestions on alerting and service level indicators.

<!--  -->
