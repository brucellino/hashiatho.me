---
layout: post
title: A platform?
date: 2025-08-17 07:00 +0100
headline: What if Hashi@home was a platform?
categories:
  - blog
tags:
  - vault
  - nomad
  - consul
mermaid: true
---

## Why

What is the purpose of a side project?
This question of course does not have a unique answer, but depends so much on whose project it is, their priorities in life, why they felt the need to start it all, and all of those other personal factors which fall into the mix.
Certainly, as a side project, it is something extra, something of secondary importance, something that supports, or augments the main thrust in life.

But we are not talking about arbitrary side projects here, we are talking about this side project -- Hashi@home.

So, what is the purpose of _this_ side project?

At this point in life, I am a professional, and have a set of skills which I use to earn a living.
I'm not out here learning technical skills so that I can start a career.
Instead, I am putting my understanding of industry to the test in a context of learning.
Let us compare Hashi@home to a gym rather than a competitive race.
A place to refine understanding, to repeat actions, to hone, to harden, to persist muscle memory.

The question then becomes -- are we building the right muscles?

Replying that the answer may be subjective is certainly unsatisfactory to the reader, so again I will give the answer for my experience and career level.
This project is about learning skills that solve problems and provide value in the real world.

That would be a perfectly good motivation to undertake a side project by itself, but we must also accept that the fact that in order for me to want to do something, even if it is in my own personal professional interest, it has to provide personal satisfaction.
Learning a skill just because customers want it is not the path to satisfaction; doing something just to get paid for it is the path to burnout and depression if you ask me.

So, I have a satisfactory answer for why I have this side project.
The trick is to find those skills that I find both elegant and worth learning, that are at the same time able to provide value in the real world.

## What

At the start, those skills were small:
Understand the Hashicorp ecosystem; build clusters of their products; find deployment patterns that worked; identify the use cases for my personal needs at home.

Part of the reason for choosing Hashicorp products is their elegance when deployed in concert, each supporting and enhancing the others.
Part of the prolonged stimulation they provided me was indeed this loop they ran around each other, a practical paradox which required a human to step in and provide the deus.

But that stimulus was purely within - a game I could play with myself, and share over beers.
A mental exercise that didn't provide anything of value to anyone else but myself.

Each of these tools did something useful, and together they provided a rich ecosystem to grow workloads in, with some configurations providing better experience than others.

### A platform

The pattern of **platform engineering** emerged a few years ago, as a response to Heavy D's insistence[^heavyd]:

> Now that we've found stuff, what are we gonna do with it?

On the face of it, an elegant proposition: take the pieces of infrastructure you have, and organise them into "planes", with clearer boundaries.
Focus on _function_, and organise interfaces in order to promote certain workflows which provide faster paths to production.
Build high-quality re-useable components so that whoever wants to deploy workloads can use these with confidence.
The result: safer, faster delivery of workloads, reduction in spread and waste.
That's all good from a business point of view, which is a good start, but I speak for the operators.

My motivation for building a platform is to make the life of the **operator** more enriching, less stressful, more attractive.

## How

Is platform engineering just hype?
Me being me, I would have to build one myself in order to answer that question.
Was it really a good pattern that could be used in varied scenarios, or was it a way for IT-types to justify their investment in Kubernetes?
I have my opinions, but without direct experience, those opinions aren't worth much are they?
The only way to have a real opinion, is to try to build one of these platform thingys myself, which brings is directly to the question of "how".

Let's start with the tooling.
I've always had great skepticism regarding the implied requirement that building a platform meant building a platform _on Kubernetes_.
I refuse point blank to use Kubernetes at home, and I strongly suspect that, for what _I_ want to build, Hashi can provide me with what I need.
It's not going to implement the _general_ patterns of platform engineering, but I actually don't want to solve that.
I want to build a platform for a specific scope and duration, not for arbitrary teams in MegaCorp.
This is far more valuable to me in both work and life[^consulting] right now.

### Teleology

First comes design.
Our design has an end goal, it is a _directed_ design, something which is guided by whether it is fit for a determined purpose.
That purpose itself may not be of great interest, but to satisfy -- or perhaps to further stimulate -- the curious, we will simply anticipate here that this purpose is to support managed services.

The platform will have a very limited set of users, will satisfy service management standards, and will be able to support arbitrary IT services used by a wide range of end-users.

The platform, if it is a product, will have purely "internal" customers, and very few of them.

### Components

Now that we have design principles, we can sketch the architecture in terms of components.
That will be work for the future, but these components should implement various planes of the platform -- the developer plane, the integration and delivery plane, the security plane, the resources plane, and the support services plane.

Each plane should take the form of one or more Terraform modules, should make clear demands on its dependencies and should provide clear functions to other components which express it as _their_ dependency in turn.

Expressed differently, the platform should be composed of independent, interlocking pieces which are designed to be put in place in concert with each other.

There will be some explicit coupling between components, but a design goal is to reduce these to a minimum and instead provide guides and patterns for deploying the platform in specific configurations.
Some components will make state explicit via Terraform, others will help the platform tend towards desired state with control loops via the Operator Pattern.

We will also try to keep the tooling footprint explicit and small.
Vault, Consul and Nomad will form the bedrock.
LGTM will provide observability.
When operators need to be written to implement controllers, they will be written in Go.
Other choices along the way will be documented according to architectural decision records.

The whole thing should be reproducible starting from any point, using existing components.


## Will it really be a platform?

Whatever I end up building, I'm going to call it a platform.
I don't care if you don't like it because it doesn't assume that Kubernetes is the API.
I'm going to focus on patterns, choosing the smallest possible toolkit that also helps me to eliminate toil.

Users will be expected to do things "our way", not whatever way they want.

Whatever the outcome, yes this will be a platform... but it will be a platform for the operators.

---
[^heavyd]: Whatever, you get it.
[^consulting]: It is also one of the reasons I found consulting so frustrating, since one never had the liberty to design an actual solution, but needed to keep general patterns in inventory, forcing them to fit into budget on a case-by-case basis.
