---
layout: post
title: Platform identity services
date: 2026-08-27 10:00 +0100
headline: Ok, but how do I log in? Keycloak as an identity broker for actual humans
toc: true
toc-levels: 4
mermaid: true
categories:
  - blog
tags:
  - nomad
  - vault
  - consul
---

Building a platform is all well and good, but it's no use if only the Boss Man can use it.
How do we set things up so that other people can actually access the services in the platform?

This is such an obvious question that it has gone overlooked in Hashi@Home until now, because I am the only one using the platform!
Specific tokens issued to me by Vault, Nomad and Consul have been enough for me to access the services and be productive with the platform itself, but this is not acceptable in a scenario where there are (shock!) several users with different roles and permissions.

## Identity architecture

When we say "identity", we mean usually mean

> a digital representation of a person which can be used to authenticate a human

Authentication is the means of providing a proof of your actual identity to a computer, but it is often accompanied by the natural next step: **authorisation**[^noz].
Authorisation is the means of granting **permission** to a human to access a given service, and when at access is granted, deciding on what level.
Another term which is used to describe the "level" of permission is the "role" that the human identity assumes inside that service.

Put together, these two terms authentication and authorisation are often referred to as "AuthN/Z", such is the frequency with which these concepts coexist.
In the ancient past[^2010], each service had an internal representation of its users, and therefore contained the identities as well as the policies for authorisation.
One of the many downsides to that approach was that identities are duplicated across all of the services which the user wants to use[^many-other-downsides].
In the enterprisey olden days[^2020], a separation of concerns was introduced where an _identity provider_ was introduced to the picture to act as a central source of truth for identities, but applications still contained their own authorisation engines internally.
In this scenario, although the identities -- and thus the user's credentials (_i.e._ passwords) -- were centrally managed and duplication of identities was addressed, each service still needed to be configured individually.
The generalisation of this this approach gave us the [Open ID standard](https://openid.net/specs/openid-authentication-2_0.html), which provides a way to reliably exchange identities in a decentralised manner.
The duplication in user identities was addressed, but there was still sprawl and lack of governance and compliance.
Subsequently, the [OAuth standard](https://datatracker.ietf.org/doc/html/rfc6749) was developed, providing an authorisation layer to the identity infrastructure.

To make an long and complicated story considerably shorter[^aai], the combination of these standards into identity providers and authorisation frameworks allows is to start speaking of "AAI"[^myaai]:

> "Authentication and Authorisation Infrastructure": **AAI**
>
> - The set of standards and tools which permit the decentralisation of identities and access policies, permitting service providers and identity providers to independently manage their data.
> - The infrastructure which permits access to services based on policies defined by services

We are finally close to what we want for our platform - a thing that can define policies, as well as connect identities to services with permissions defined by those policies.
We will be using Keycloak to implement this authorisation and authentication layer, finally giving us the ability to permit access to platform services without having to also manage the identities of our platform users.

We are going to call this the _"Identity Architecture_".

## Implementation of Identity Architecture

The context of the platform identity service is shown in the diagram below, where it is designated "Authentication and Authorisation Service".

```plantuml

{% include diagrams/identity-arch-1.puml %}

```

### Access: Authentication and Authorisation workflows

In this context, someone wishing to access one of the Platform Services[^NotWorkloads] is redirected to the AAI, which then requests authentication of the user at their organisatin's identity provider (IdP).
After successful authentication, the AAI looks up what the user's attributes as defined in the authorisation realm, and then passes those to the service which the user initally wanted to use.
The service's policies then map those attributes to permissions and roles in its context, and authorises the user to access it with those same permissions and roles.

This is shown in the sequence diagram below:

```seqdiag
seqdiag {
  User -> Service [label = "Request Service"];
  Service -> AAI [label = "Request AuthN/Z"];
  AAI -> IdP [label = "Authenticate User"];
  User -> IdP [label = "Provide Credentials"];
  IdP -> AAI [label = "Return Identity"];
  AAI -> Service [label = "Provide Attributes"];
  User <- Service [label = "Authorise with policy"];
}
```

As the platform owners, we need to deploy the AAI service, synonymous with "Platform Identity".
This means we are responsible for issuing standard-based attributes to authenticated identities, so that services can decide what permissions and roles to assign to those identities.

These abstract services take the following form in our platform:

- Platform Identity: A [Keycloak service](https://www.keycloak.org)
- Identity Provider: An LDAP service configured as the [Keycloak external storage provider](https://www.keycloak.org/docs/latest/server_admin/index.html#_user-storage-federation)

### Identity in the Platform Engineering Context

The Keycloak service will serve as the Identity service as part of the Platform Security Plane -- let's remind ourselves of the overall design as of summer 2026[^parts-missing]:

<div class="figure" align="center">
  <img src="{{ site_url }}/assets/img/platform-26-08.png" width="70%">
</div>

Keycloak sits in the ID management component of the Security Plane.
The external identity store (The LDAP directory of identities) is not shown, because indeed it is not _part_ of the platform, but actually owned by the organisation which is the _customer_ of the platform.
We attach our platform to it in order to allow the organisation to retain sovereignty over their identities.

Before we close the section on architecture, let's take a closer look at the Keycloak component diagram.

#### Container View

Consider the case where the platform operator wants to access the Vault instance:

<!--```structurizr

{% include models/platform-identity.dsl %}

```-->

<!--

Add the C4 diagram for identity, showing the software system and external services

Software system is platform identity, external services are platform services.

-->
```d2

{% include models/platform-identity.d2 %}
{% include models/platform-identity-container.d2 %}

```

Keycloak's OIDC endpoint acts as a [Vault Authentication method](https://developer.hashicorp.com/vault/docs/auth/jwt/oidc-providers/keycloak).
Keycloak is configured to use the LDAP external identity store as a source of truth for identities.
If the user us able to provide valid identification credentials for that identity, Keycloak returns valid authorisation claims, and Vault authorises access to the user.

So far, so good -- the architecture can work.


#### Component View

There is more to the architecture than just the containers of the software system.
This high-level view of the architecture does not yet reveal the dependencies in terms of platform services and flows.

<!--
Add a component view to each of the services.
-->

```d2

{% include models/platform-identity.d2 %}
{% include models/platform-identity-component.d2 %}

```

Now, we need to consider deployment models and their tradeoffs.

## Deployment Scenarios

Let's define a few hypothetical deployment scenarios.
These can be split grosso-modo between deployments _in plane_ and _out of plane_.


> "In plane" deployments place the services in the Platform Resource Plane, meaning that the services themselves are orchestrated by the platform itself while "out of plane" deployments mean that the services are not orchestrated by the platform, but by some external controller.


This external controller would be something independent, bound to the deploy environment and independently managed, such as a SystemD unit on a virtual machine, or a an independent orchestrator on an external control plane.

### Combined deployment in-plane

In this scenario, we deploy the authentication and authorisation services as a single workload into the resource plane.

This means we write a single Nomad job which contains the relevant tasks and services for both the LDAP backing service, as well as the Keycloak service.


<!--
identity source in database, file or other
admin creds in vault
seed consul KV
use kv as template to openldap job

openldap job contains server and replicas
add  custom attributes for platform.

-->

```d2

{% include diagrams/2026-08-07-combined-deploy-in-plane.d2 %}

```

As can be seen in the scenario, we are dependent on the existence of a managed PostgreSQL cluster for the deployment of the Keycloak service, which will be expecting a database persistence layer for its data.

#### Discussion

In this scenario, we have the benefits of:

1. **Single definition of workload**: we deploy everything we need with a single `nomad.hcl` file.
1. **Network namespace sharing**: Keycloak can access the LDAP server on the local network since they share a Nomad network
1. **Allocation filesystem sharing**: The Nomad allocation system makes available a shared filesystem for the deployment if they need to share files; each task also has access to its own private files and secrets.

However, we also have the potential downsides of:

1. **Resource exhaustion**: Since both keycloak and ldap are declared in a single group, they will be placed on a single node. If there are not enough resources, the orchestrator may not be able to place them. This is particularly bad if the node hosting the allocation becomes unhealthy in the cluster.
1. **Monolithic deployment**: Somewhat linked to this negative aspect is the fact that the deployment is monolithic - it becomes difficult to independently scale each of the tasks in it. This is not a concern to us initially, but is of great importance when we start to consider production readiness.

As a first step though, this is a good starting point.
It is simple, easy to understand, self-contained, and has specific external dependencies.

Just for the sake of argument, let's see what a factorised deployment would look like.

### Factorised in-plane deployment


### Out-of-plane deployment

The out-of-plane deployment assumes that we have dedicated resources somewhere for these services.
This may be conceived of as a more static deployment model, with dedicated machines in dedicated environments being allocated manually to this workload.
The workloads (LDAP, Keycloak) and perhaps even their direct dependencies (Database backends, DNS resolvers, persistent storage claims, local filesystems, _etc_) are directly provisioned on these dedicated machines via some form of configuration management[^Ansible]

---

## Footnotes and References

[^noz]: Don't come at me with your weird American spelling. I know everyone calls it AuthN/Z where that zed grinds my nerves, and I know I'm not going to be able to change it. But by Zeus I will spell my own writing properly!
[^2010]: I'm referring to the early to mid-2010s here.
[^2020]: I'm referring to the early 2020's here
[^many-other-downsides]: That's just _one_ of the downsides -- there are plenty others, ranging from security considerations, to operational and compliance concerns.
[^aai]: The way I have described it here is far too simplified to be taken seriously, and mainly for my own purposes of creating a short narrative of what components we are deploying. The ecosystem comprising tools and standards to create AAI (Authentication and Authorisation Infrastructure) is far more complex, but it's not my place to go into it here.
[^myaai]: This is an incomplete definition of AAI, solely for the purposes of this article. Good luck finding an authoritative definition of AAI, and if you do, please send it to me.
[^NotWorkloads]: Recall that when we say "Platform Service", we are referring to services in platform planes -- the orchestrator (Nomad), the secrets engine (Vault), _etc_. These are **not** the deployed workloads, often also called "services", which are configured to use the federated AAI. In the case of EGI services, this AAI service would be Check-In.
[^parts-missing]: As you can see, there are several parts missing. Some are missing by design (we don't advocate a single IDE, we don't have a portal, we are not interested in FinOps), while some are still waiting for proper integration (OPA as policy engine, SemGrep and Report Portal as code quality and testing). Stay tuned
[^Ansible]: I'm not coming right out to say it here, because I wanted to write this as if there were some arbitrary out-of-plane controller here, but it has become unwieldly talking around the fact that this is in all effects a set of Ansible playbooks against a set of VMs.
