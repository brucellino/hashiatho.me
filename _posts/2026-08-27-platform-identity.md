---
layout: post
title: Platform identity services
date: 2026-08-27 10:00 +0100
headline: Ok, but how do I log in? Keycloak as an identity broker for actual humans
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

<pre class="mermaid">
{% include diagrams/identity-arch-1.mmj %}
</pre>

---

## Footnotes and References

[^noz]: Don't come at me with your weird American spelling. I know everyone calls it AuthN/Z where that zed grinds my nerves, and I know I'm not going to be able to change it. But by Zeus I will spell my own writing properly!
[^2010]: I'm referring to the early to mid-2010s here.
[^2020]: I'm referring to the early 2020's here
[^many-other-downsides]: That's just _one_ of the downsides -- there are plenty others, ranging from security considerations, to operational and compliance concerns.
[^aai]: The way I have described it here is far too simplified to be taken seriously, and mainly for my own purposes of creating a short narrative of what components we are deploying. The ecosystem comprising tools and standards to create AAI (Authentication and Authorisation Infrastructure) is far more complex, but it's not my place to go into it here.
[^myaai]: This is an incomplete definition of AAI, solely for the purposes of this article. Good luck finding an authoritative definition of AAI, and if you do, please send it to me.
