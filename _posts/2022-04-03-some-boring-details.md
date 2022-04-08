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

[![DigitalOcean Referral Badge](https://web-platforms.sfo2.digitaloceanspaces.com/WWW/Badge%202.svg)](https://www.digitalocean.com/?refcode=ed3b69c0eec6&utm_campaign=Referral_Invite&utm_medium=Referral_Program&utm_source=badge)

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

### Hashi@work

I had the great pleasure to use Terraform, Vault and Packer in a professional context a few months back.
What I gained from that was the practical wisdom of how to infrastructure components and deliver applications which use them, across a few different clouds.
My current work experience has moved on-premise, where many of the comfortable functions provided by the cloud are absent, and I have to develop components from scratch.
This gave me pause for thought on how to actually do this a way that is both _ergonomic_ for my team and I, as well as _reliable_ in the sense described above.
When, one day, I move on to something new, I would like my work and the concepts which inspired it to remain and continue to provide value to the company.

## Hashi on Digital Ocean

Due to the particular nature of the environment I'm working in, I need to have a hard separation between the work environment and my learning environment, so I started using [Digital Ocean)](https://cloud.digitalocean.com) to set up small environments to test the results of my work.

This was the first time I had used Digital Ocean in any serious way.
Compared to my professional experience with AWS, I find it refreshingly simple, but lacking in a few key areas.
For example, while there is private networking enabled by default, there doesn't seem to be any concept of an internet gateway, which the user is [expected to set up themselves](https://docs.digitalocean.com/products/networking/vpc/resources/droplet-as-gateway/).
Another aspect was the need to refer to VPCs, images and SSH keys by ID rather than name in Packer templates, which was a bit surprising, and involved some manual labour.

All of this has some implications for developing Terraform modules and Packer templates on Digital Ocean, but nonetheless I found the [pricing and billing](https://www.digitalocean.com/pricing) model congruent with the simplicity of the cloud services.
Expecting to pay a cent per VM in a test execution is a very easy mental model to have in my brain, and ultimately convinced me that I could do something useful with this cloud rather than moving to another.

## Developing re-usable components

I set myself the goal of setting up an disposable, on-demand Consul cluster.
This seemed like a useful thing in many circumstances, irrespective of environment.
The plan to do this was as follows:

1. Create a small Terraform module that produces a single small droplet on which to test Ansible roles
1. Create an Ansible role which produces a secure re-usable base image on Digital Ocean
1. Create an Ansible role which uses the result of step 1 and produces an image which can be integrated into a Consul cluster.
1. Create a Terraform module which will produced images to create a Consul cluster, along with the necessary cloud components, including DNS, certificates, _etc_.

These tasks are achievable in a few days for anyone with a bit of experience with the toolkit (Ansible and Terraform) and time to read the respective documentation, but the question is: will it be **useful in the long run.**

This is where the boring bits come into the equation, and the calculus is not trivial.
Aspects such as reliable and high-quality test coverage, documentation, guardrails and examples take more time to develop than the actual components sometimes, and are only useful when the components are actually used in production, or by others.
This is where the divergence in private and professional work becomes apparent.
Hobby work or demonstrations can be done to emphasise a smart or fun way to do something.
However, when your role is to enable others to achieve **their** goals rather than your own, the emphasis has to lie on the quality of the component rather than the mere functionality.

As a result, I have collected aa small toolkit which I now rely on to help me achieve the high quality of component I try to aim for.

- [TestInfra](https://testinfra.readthedocs.io/en/latest/): Writing good tests for compliance, functionality and security is one of the last things that is taught to DevOps professionals. My opinion is that part of the reason is the lack of a really good tool to implement write the tests in. I have used [Inspec](https://inspec.io) and [Terratest](https://terratest.gruntwork.io/), but neither of them have the built-in functionality or ease of use that TestInfra has. TestInfra is certainly lacking too, but given the Python ecosystem it's far easier (for me) to extend and write the tests that _actually matter_ and boring enough that I don't have to reconsider the tool of choice for every component I write. I have come to rely on failing tests to ensure long-term maintenance of my components, especially for Ansible roles.
- [Trivy](https://aquasecurity.github.io/trivy/): Like TFSec below, trivy is my boring choice for detecting vulnerabilities in artifacts. Together with TestInfra, I have adopted a pattern of adding provisioners to Packer templates to run these two checks on images, to break the build in the case that they fail. Trivy has a database of vulnerabilities which is reliable enough for me to automate the decision of whether to release something, and checks almost everthing I need to say with high certainty that a given artifact is safe for use in production.
- [Conventional Commits](https://conventionalcommits.org): Effectively communicating changes is important to future me and anyone who may need to maintain the component. Conventional commits is my boring first choice when it comes to selecting a vocabulary for describing changes.
- [commitlint](https://commitlint.js.org/#/): Nobody's perfect, and I probably have a place in that particular hall of fame, so I need something to catch me when I make typos in commit messages. Commitlint runs as a pre-commit hook to check my commit messages and ensure that they conform to the conventional commit spec.
- [Semantic Versioning](https://semver.org/spec/v2.0.0.html): Reliably and consistently releasing artifacts makes it possible to continuously deploy them using declarative infrastructure. A common approach is to consume a `latest` tag of an artifact (such as a repository or container image), but making atomic changes to deployments becomes impossible to track. Furthermore, it becomes difficult to reliably roll back to a known working state, making deployments risky and thus susceptible to slowing down,  forcing manual intervention and requiring human cognition. Versioning artifacts is perhaps one of the most impactful boring practices I have come to adopt, and semantic versioning is my boring choice for implementing it.
- [Semantic Release](https://semantic-release.gitbook.io/semantic-release/): If SemVer is boring enough for deciding _what_ version to assign to artifacts based on changes in the commit history, Semantic Release is my boring choice for **actually creating** the release artifacts.
- [pre-commit](https://pre-commit.com): Charity starts at home and clean consistent, working code starts before you commit it. The pre-commit framework is my boring choice for running sanity checks on changes before I commit and push them to the repository. Apart from the commit message check done by commitlint, other recurring stars in my pre-commit configuration include
  - [detect-secrets](https://github.com/Yelp/detect-secrets): ensures that sensitive data is not accidentally committed to the repository.
  - [Ansible Lint](https://ansible-lint.readthedocs.io/en/latest/): helps me ensure that roles and playbooks are written in a standardised way to respect basic levels of quality. Linting not only catches basic errors, but also helps to stay aligned with a given style guide, which greatly improves the maintainability of Ansible components.
  - [Terraform format](https://www.terraform.io/cli/commands/fmt) and [validate](https://www.terraform.io/cli/commands/validate) are no-brainers, in fact the formatting of Terraform code is usually done by the IDE itself, and having a pre-commit hook which validates Terraform code ensures that incomplete work is not committed.
  - [Terraform Docs](https://terraform-docs.io/): Ain't nobody got time for writing docs, especially in a consistent format and style. Snark aside though, I wish there were a similar tool for Ansible. Yes, I know there are some contenders, but none of the ones I've tried provide a similarly smooth experience.
  - [TFSec](https://aquasecurity.github.io/tfsec) and [KICS](https://github.com/Checkmarx/kics)

That's a pretty big list so far!
There are other tricks I've learned for specific tools, but that is probably a story for another day.
For now, I conclude my brief interlude describing the boring, invisible, but crucial bits of what I do at work.

-----

I used digital ocean quite a bit during this post, and as mentioned above, I found it quite useful for the purposes.
Go ahead and get some free credits with my referral link below.

[![DigitalOcean Referral Badge](https://web-platforms.sfo2.digitaloceanspaces.com/WWW/Badge%202.svg)](https://www.digitalocean.com/?refcode=ed3b69c0eec6&utm_campaign=Referral_Invite&utm_medium=Referral_Program&utm_source=badge)
