---
layout: post
title: Solid base images for automation
date: 2022-07-11 12:00 +0100
headline: Just join the Consul Cluster -- we'll take it from there
categories:
  - blog
tags:
  - packer
  - raspberry-pi
---

## The quest for a no-touch deploy

In the early days of Hashi at Home, I tried to build a mental model of what I was doing.
It was important that this model be more or less _linear_ with a specific starting point and a clear progression of states from that, linked by edges.
Having a linear mental model would make it not only possible to represent the progression of the platform from bare hardware to something we could deploy jobs on, the main benefit for me would be to have something that I could _execute_.
I wanted something that could be reliably and reproducibly recreated, barring of course dependencies on specific data which lives outside of the graph, _etc_.

I wanted the bare minimal manual actions to be required when deploying
In other words, the amount of magical knowledge required to rebuild my "datacenter" should tend to zero.

I had accepted that there would have to be some hands-on tasks -- we are dealing with cheap little pieces of hardware after all -- but the way I have fallen into doing it until now seems unnecessarily mechanical.

## Some knowledge required

It soon became apparent to me though that the goal of _zero_ manual actions, or specific information was impossible.

When I want to deploy (or completely rebuild) a new computatom, the procedure usually involves some pointing and clicking, and inevitably sucks away my time on the weekend.
Using the [raspi-imager](https://www.raspberrypi.com/software/), I usually have to perform the following tasks, in serial fashion:

1. Select the desired base image (usually Raspi-OS 64bit)
1. Add basic configuration details:
   1. username with ssh key
   1. wifi configuration
   1. hostname
1. Flash the microSD disk
1. Insert the disk into the computatom and boot it into the network.

Usually this kind of maintenance happens rarely and in bursts, perhaps when I want a do-over, or when faster, better micro-SD disks arrive and it's time for an upgrade.

In this cloud-native world, it's important to remember that these are physical bits of metal and plastic that have to be moved around from place to place.
There's no API for "eject from my laptop and transfer into the pi across the room"[^yet].
"Starting an instance" means actually booting off a microSD card with a machine the size of a credit card.
There are no racks or robots here!

The key point is that the image should have the bare minimum knowledge in order to join the Consul cluster without the operator having to do anything.

## A Hashi image is a happy image

The raspberry pi imager is really a great piece of software.
Simple, reliable, provides a useful set of customisation for creating an computatom that will join the network when it boots.
However, it doesn't provide _enough_ customisation for me.
Yes, I could flash a different image from the [upstream Rasperry pi](https://www.raspberrypi.com/software/operating-systems/#raspberry-pi-os-64-bit) one, and indeed this would go a long way to satisfying my needs.
However, it still doesn't provide the capability to create custom partitions, filesystems, _etc_.
This missing feature is driving me back into the welcoming arms of Packer who I have loved and trusted so much in the past to create my images.

Creating images at home is a bit different from creating them in the cloud though.
Whereas previously I could follow a straight and paved road from base image to final image, in this case I needed to stray somewhat.
This isn't as simple as merely taking an upstream, making minor modifications and pushing to a registry somewhere, such as an EBS block or container registry.

### New builders and post-processors

Here's my Nirvana for building images: **start with a clean upstream image and end microSD card that I can slot into a pi.
The part in the middle -- [the provisioner](https://www.packer.io/docs/provisioners) -- is the same old tried and trusted Ansible provisioner, but what do I do for the builder and post-processor?

First of all, I need a builder that can read ARM64 images.
Secondly, I want a post-processor that can flash a microSD card.
Is this asking too much?

Well, it turns out that perhaps it isn't.
Browsing the Packer [community supported builders](https://www.packer.io/docs/builders/community-supported), I came across the two ARM builders available.
Mateusz Kaczanowski's [ARM packer builder](https://github.com/mkaczanowski/packer-builder-arm) even supports custom partition tables and a flashing post-processor which is kinda exactly what I want!
Nice. I can't see the end of the road yet, but the way seems fairly clear.

### Land gracefully

I need computatoms to join the **Consul datacenter** when they boot, not just the network.
This implies of course that they already have Consul installed, and have the information necessary to configure themselves when they start up.
I would like to approach an autoscaling parallel where new instances automatically join the cluster and are available for work -- without leaving secrets on the image.
Of course, zero trust isn't _absolute_ zero trust!
What I can say for certain is that I will need to provision the Vault Agent, Consul template and Consul itself as a bare minimum.
Configuration should be as dynamic as possible, with less reliance on configuration files and more reliance on the templating features that Consul startup arguments offer.

### Authenticating the _machine_

In a zero trust world, authorisation is based on the identity of the entity, so in order for the Vault agent to authenticate, it needs some form of _identification_.

In the past we could have assumed that since a machine was on a local network, it should have implicit access to all the required secrets and sensitive data, but we know that in a cloud native environment making this kind of assumption often leads to failure.
We cannot assume that the network will be trusted, or even that it will be _that particular network_!

In order to authenticate the machine then, we need to issue it some kind of credential, without persisting secrets on the image.
Luckily, Vault has just what we need, in the form of the "pull" method[AppRole](https://www.vaultproject.io/docs/auth/approle).
Issueing a Role ID to an instance and allowing it to retrieved a wrapped token, we are able to securely provision files templated with the sensitive data we need -- Consul gossip key and CA certificates -- to agents when they start.

### Storage Configuration

As mentioned above, I need a builder that will allow me to create custom partition tables with specific mount points for filesystem partitions that will later support a distributed storage system at home.
The [CSI](https://github.com/container-storage-interface/spec/blob/master/spec.md) drivers want to manage a filesystem in many cases, instead of a directory.
Minio also wants to [manage its own _drives_, typically mounted on specific disks](https://docs.min.io/docs/distributed-minio-quickstart-guide.html).
Well, we don't have disks but we still need to provide it with a filesystem mount.

The raspi-imager doesn't provide this luxury.
It formats the entire disk to include all of the space available, whereas I want to leave a few GB for other partitions.

## Watch this space

Work has started on all this fun stuff over at the [Ansible role for Consul](https://github.com/brucellino/ansible-role-consul) repository.
In the next few weeks, I should have a writeup of how to provision perfectly configured, zero-trust, zero-touch images with Packer for bare-metal raspberry-pi deployment.

Stay tuned!

---
[^yet]: I mean... not _yet_. I can imagine how this kind of thing would be possible by netbooting or mounting a remote store for first boot. Alas, Hashi@Home is not there yet.
