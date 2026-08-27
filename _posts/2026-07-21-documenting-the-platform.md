---
layout: post
title: Documenting the platform
date: 2026-07-21 13:00 +0100
headline: Documenting the platform
categories:
  - blog
tags:
  - nomad
  - vault
  - consul
---

When I first started out on this little hobby, it was out of a rejection of the hegemony of Kubernetes.
Even back in 2019 there was an irresistible pressure to "standardise" on an "API" by  identifying that API as the Kubernetes API.
My feeling was then and still is that the only good reason to conflate those two things was that everyone else was doing it.
I must first confess that as the Kubernetes ecosystem has evolved and matured I personally not bothered to keep up with it, so whatever criticisms I may betray, they are not based on an informed analysis.
I must first write that down, even if only for myself, because my contrarian position has always been less of a rejection of mass-adoption of a mature technology, and more exploration and analysis of the underlying principles which make that technology relevant.

I've spent the last 5 or 6 years chasing quality, operability, economy, functionality -- the things that make building and using technology pleasurable and fun, things that put people back in the centre of design.
The physicist in me thinks that a phenomenon isn't real until it's independently-measured.
That means there is inherent value in pursuing this smaller, more niche experiment in platform engineering, even if only for myself, even if only for _understanding_ rather than simply knowing how to build platforms.

And on that point: what better way to show comprehension of the platform than documenting it for whoever might want to use or extend it?

## The difficulty of documentation

I am old enough to have failed at documenting projects more than a few times now.
Now, any project of substantial size must be documented if it is to live beyond the attention span of those who initially drive it.
With the benefit of hindsight, I put it to the reader that good documentation is the single most important factor in predicting the longevity and uptake of a product or project.
If it is so important then, why is documentation so consistently terrible?
A long list of examples and counter-examples of projects with bad documentation might reinforce my point here, but honestly, dear reader, you're going to have to just trust me.
The documentation of the software underpinning even global infrastructure projects such as the LHC compute grid is so woefully lacking as to be entirely counter-productive.
Again, due to the fact that this is a personal blog, I will permit myself the liberty of not providing any actual evidence, but I have a few comments on what went wrong[^get-in-touch]:

1. Documentation started where nobody was and ended where nobody wanted to go
2. Writing documentation tried to create content without regard for form.
3. No instructions were left for how to fix or extend documentation
4. Documentation never made it clear when it was referring to obsolete components, or whether it itself was obsolete.

These points, which are merely those on the tip of my consciousness right now and are certainly not the whole story, may be summarised perhaps thusly:

> Documentation was written by those who know, for those who know, with the single aim of reminding themselves of what they already knew.

## What is documentation even for

So, what is the _actual_ aim of documentation?
What _should_ it be?

With the goal of writing actually good documentation, I think the first thing we need to recognise is that different kinds of documentation are necessary for both different kinds of _people_ as well as for different _imminent goals_.

The [Diataxis](https://diataxis.fr/) framework said it best:

> Diátaxis identifies four distinct needs, and four corresponding forms of documentation - tutorials, how-to guides, technical reference and explanation.

Restarting a documentation journey from this principle -- that there is different documentation for different times and needs -- provided clarity on what went wrong, and how to fix it.
Most of the documentation that I remember as bad was of the "how-to" kind, but everything else was missing.
No architectural, design or historical overview, no concise reference to bookmark and refer to whenever a tool needed to be used
When these were present in some form, the language format and organisation made using the documentation to something specific too much of a pain.

## A better way, with better tools

So, we need to write documentation for our thing at different levels.
We must accept that there is no linear path from an agreed on "starting point", through ever more information, towards a global understanding of the system.
Users of the documentation who want to achieve some goal initially might start with a howto for some specific desired endpoint, others who want to contribute and extend the documentation might start with the explanation of a function or component.
This means that we would do better too to have a modular architecture for the documentation itself.

The shape of  the documentation should mirror the shape of the platform.
The platform engineering pattern starts with the abstraction of "planes" where services and functions are deployed with a finality in mind, with a goal of providing a certain higher-level abstraction such as "databases", or "workload orchestration".
The documentation of these planes cannot start at the level of a tool or piece of code, because they are _concepts_, so we need to document the _concept_.
The concept can be implemented in several ways, hence my whole diatribe in the first part of the blog post, but the explanation of the concept serves a different purpose than the description of how it was implemented.
Too often in the past, only the description of how it was implemented, rather than the concept itself, has been written down and sparingly even then, so as to serve only to remind the author what they were thinking at the time.

In order to do this properly some of the documentation should reside with the tool it is documenting, perhaps even in the same repository.
But on the other hand, as our example just now shows, some documentation is not about any particular component or thing, but about explaining higher-level abstractions which emerge if you build it right.
This documentation should reside in the "ideas" repository, or rather a dedicated documentation repository which changes at a different rate and with different goals to the individual components and their implementations.
If we accept this "documentation by parts", we are then soon led to the issue of complexity -- how will we then combine the parts into a whole?
Or are we to accept different documentation residing in different places, as has always been the case in the past, to our lament?

Fortunately, it's 2026 and we can now have nice things.
A combination of an expressive, compilable markup language and a framework for building documentation from multiple sources has matured into what feels like the right solution.
Using [AsciiDoc](https://docs.asciidoctor.org/asciidoc/) and [Antora](https://docs.antora.org/antora/latest/) to write and build our content, and the Diataxis principles to organise it, I finally feel like it's worth writing documentation again.

## Docs for Hashi@Home

So, I have decided to embark on an effort to write documentation for Hashi@Home as if it were a platform, for the same reason as I started this project in the first place: to see if I could actually do it.

"What if Hashi@Home were a platform?" I asked previously -- well then I would need to satisfy the primary aspects of what makes something a platform:

* Self-service
* Golden Paths
* Managed as a product

The first two are user-focussed, documentation written from the point of view of a user who wants to _use_ the platform and its functions towards some secondary goal -- their own workloads.
This documentation needs not explain how to deploy, extend and maintain the platform itself, but rather what functions are available, and how to get value out of the platform by deploying their own workloads.

The second is about the platform itself.
Documentation of the platform should include all of the technical information for owners and operators of the platform, including specific playbooks for deployment, monitoring and operations.
The documentation should put the owner of the platform in the position to deploy the entire thing from scratch, making informed choices along the way, describing the overall path and goals, as well as the golden paths to get from one state to the next.

This is a *lot* of documentation... I don't think it will become complete in any sense anytime soon!
But even before writing it, I can see its shape and how to build the right thing.


---
## References and Footnotes

[^get-in-touch]: If anyone takes serious exception at these words, I really sincerely do look forward to having a constructive confrontation with you!
