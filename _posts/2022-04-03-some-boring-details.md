---
layout: post
title: Hashi@work -- part 1
date: 2022-04-03 08:00 +0100
headline: What if my home were a workshop for actual work?
categories:
  - blog
tags:
  - consul
  - cloud
  - digitalocean
  - packer
  - reproducibility
---

## Introduction

It has been about a year since I got it into my head that I wanted to play with what Hashicorp built.
The draw of these well-designed tools was strong enough for me to invest a few hundred euros in a bunch of hardware, set it up in my home office and use them for my own benefit.
Doing so has helped me gain practical knowledge of how distributed systems actually work -- and more importantly _fail_.
I have tried to write the code necessary to deploy my own environment, which has its own set of peculiarities.
These are physical, well-identified bits of hardware -- my so-called computatoms -- which sometimes even have appendages which only they know about, the HATs.
Kernels need to be customised, libraries need to be present or absent, _etc_ and this makes them much closer to pets than to cattle.
In order to do things properly at home, I need to treat my computatoms more as individuals and less as an amorphous blob of compute.
This is at odds with many of the principles that I put into action at my day job -- hermetic builds, immutable images, infrastructure as code, _etc_.

## Priorities at home and at work

For Hashi@home, my priority was intensely personal. **I** wanted to learn, **I** wanted to experiment, **I** wanted to build and feel the satisfaction of something done with my own two hands.

Different priorities are at play when you have to do things for other people.
My experience so far has been that the most useful thing that you can do for others is be _reliable_.
Reliability doesn't mean that what you do never fails or works perfectly first time, every time -- rather it means that people know what to expect when you do things for them.
To put it differently, what people need is **not perfection, but consistency**.

In practical terms, the difference is putting into practice principles which can be succinctly surmised and understood intuitively by the people I serve.
These the boring, but important aspects of professional life, and as such, they have such wide-ranging impact that they can be considered standards of practice in many cases.
As such, they have been studied in diverse situations, and in many cases, codified into executable implementations.
I'm referring here to basic, but crucial things such as code quality and conventions, release engineering, and requesting, tracking and delivering work, amongst others.
I've taught at a lot of two-week boot camps, research projects and the like where the aim was to get a project up and running and deliver a MVP, but almost always, these fundamental practices are excluded from the curriculum.

## Hashi@work

I had the great pleasure to use Terraform, Vault and Packer in a professional context a few months back.
What I gained from that was the practical wisdom of how to infrastructure components and deliver applications which use them, across a few different clouds.
My current work experience has moved on-premise, where many of the comfortable functions provided by the cloud are absent, and I have to develop components from scratch.
This gave me pause for thought on how to actually do this a way that is both _ergonomic_ for my team and I, as well as _reliable_ in the sense described above.
When, one day, I move on to something new, I would like my work and the concepts which inspired it to remain and continue to provide value to the company.

### Hashi on Digital Ocean

Due to the particular nature of the environment I'm working in, I need to have a hard separation between the work environment and my learning environment, so I
