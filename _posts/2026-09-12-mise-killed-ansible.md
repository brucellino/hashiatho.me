---
layout: post
title: Mise killed Ansible
date: 2026-09-12 10:00 +0100
headline: Now that we have bootstrap, what is Ansible even for?
toc: true
toc-levels: 3
categories:
  - blog
tags:
  - packer
  - mise
  - ansible
---

One of the most important aspects of platform engineering is building reliable images that can be deployed as workloads.
This concept - that there is something to _run_, is so deep in the stack that we often forget that everything needs to be packaged.
Pulling somebody else's packages from a registry is commonplace and unremarkable now, and we usually refer to these as "dependencies", but if we want to do something more useful, we need to bring our own artifacts to the environment.

Until around late 2022, I've tried to keep tooling strictly within the Hashicorp stable, because I wanted to set a challenge for myself.
However, this turgid little side project started turning into something more like what I've always wanted to build -- an actual platform -- during 2023-2025.

I always wanted to keep things elegant and simple, using the smallest number of tools, decisions, surprises, _etc_ possible.
One should be able to look at the system and understand it.
One file is better than one which reads another three...
One tool that does everything well is better than one which co-ordinates another three.

Of course, the principle of using a tool for its intended purpose remains - don't use a screwdriver as a hammer.

This basically meant that for building reliable images, I did the following:

* Declare a packer template for an artifact. Packer template exist only as a declaration for the artifact, provisioning happens via it with the right tools. The same artifact for arbitrary targets could be built
* Design a provision model. This typically meant writing something abstract like an Ansible role which could be used and tested independently. The concept of dependencies and re-use of roles was inherent in the design.

## Reconsidering reusability

I chose Ansible as part of the platform playbook because it provided a very stable, very extensive framework for applying whatever provisioning might be needed to my inventory, at any level of deployment, from bare metal up.
It was close enough to writing declarations rather than procedures.
I could factorise layers using Ansible Roles, and build target states out of compositions of them.
This all seemed like very good engineering when I was deploying virtual machines with lots of things inside them.

It's not 2019 anymore, and a lot of assumptions of what is good design need to be revisited.
A new principle might be something like "everything can be understood on its own" might be a good one.
A principle which is still good is: "less is more".
Ansible is definitely not "less"

## Provisioning with Mise

Along has come a tool which seems to do a lot of things right: [_Mise-en-Place_](https://mise.jdx.dev), or just `mise`.

Mise bills itself as

> A comfortable home for your development workflow.
>
> -- _[mise.jdx.dev](https://mise.jdx.dev/)_

I first started using it to replace all of the language-specific package managers (ruby, java, python, go...).
The ergonomics were immediately attractive and left no need for further convincing.
All through 2024 and 2025, Mise became the _only_ way to provision a runtime[^thisblog].

Of course, this only provisioned userspace things, which was indeed what I wanted, but the user of those userspace things still needed to actually be provisioned, typically by something else.
The system needed to be bootstrapped, shall we say, with users, packages, and some other configuration which was typically outside of user space.
This was the part typically reserved for Anisble, which could trundle in under SSH and do root-level things to the image.

Mise has recently added a "bootstrap" function, which seems to be pushing out the need for Ansible however.

## Mise en Production -- Indico

It's time to take this seriously.

I want to illustrate how I can build artifacts for production-grade workloads without Ansible.
Let's break the playbook, and see if we can put it back smaller, and with fewer parts.

The process will be pretty much the same: write a Packer template and provision it; but the provisioning will be split between a Mise bootstrap and a Mise application runtime.

Let's start with the basics:

{% highlight hcl %}
# Indico image for platform deployment
packer {
  required_plugins {
    docker = {
      source = "github.com/hashicorp/docker"
      version = "~> 1"
    }
  }
}
{% endhighlight %}

We will build only one artifact, the docker container, so we only declare the one plugin as well as a docker source:

{% highlight hcl %}
source "docker" "indico-base" {
  image = "ubuntu:24.04"
  commit = true
  changes = [
    "USER indico",
    "WORKDIR /opt/indico",
    "ENTRYPOINT /bin/bash -l"
  ]
}
{% endhighlight %}

Indico documentation [assumes virtual machines](https://docs.getindico.io/en/stable/installation/production/deb/#debian-ubuntu), so we try to start as close as possible to that, even though we can very likely improve this base image.

From that source, we declare a build with its provisioners:

{% highlight hcl %}
build {
  sources = ["source.docker.indico-base"]

  provisioner "shell" {
    inline = [ ... ]
  }
{% endhighlight %}

The first provisioner is to add mise itself.
The actual inline is ellipsised, but is taken from [Mise's documentation](https://mise.jdx.dev/getting-started.html)
If we had a base image with _just_ mise, we could skip this and only add the mise configs

Once Mise is installed, we need to provision the declarations for the system and the application.
I chose to do this separately for now because the first (bootstrap) runs as root, and the second (application) as the user provisioned _during_ bootstrap.
There seems to be a clear separation in stages here, although I may be missing something.
A more elegant way would be to do a one-shot provision of everything with the correct permissions, _etc_, but we don't seem to be there yet.

We provision these configuration files with Packer's [`file`](https://developer.hashicorp.com/packer/docs/provisioners/file) provisioner:

{% highlight hcl %}
  provisioner "file" {
    source = "mise.bootstrap.toml"
    destination = "/root/mise.toml"
  }
  # The second is the runtime for the application
  provisioner "file" {
    source = "mise.indico.toml"
    destination = "/tmp/mise.indico.toml"
  }
{% endhighlight %}

Then we bootstrap the machine:

{% highlight hcl %}
  provisioner "shell" {
    inline = [
     "cd /root/",
      "mise trust",
      "mise bootstrap",
    ]
  }
{% endhighlight %}

This would be the equivalent of a "bootstrap play" by an Ansible playbook, except it runs directly on the machine, and takes a few seconds.

Now we provision the application - add environment and application dependency declaration and apply:

{% highlight hcl %}
  provisioner "file" {
    source = "requirements.txt"
    destination = "/opt/indico/requirements.txt"
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -exo pipefail"
    {% raw %}
    execute_command = "su - indico /bin/bash -c '{{ .Vars }} {{ .Path }}'"
    {% endraw %}
    inline = [
      "cd /opt/indico",
      "mise install",
      "mise tasks run install"
    ]
  }
{% endhighlight %}

There are only 3 phases:

1. Add Mise
2. Bootstrap the machine with configuration files
3. Provision the application and its environment

Again, given a better base layer, the first (add Mise) can be removed.

This looks incredibly simple, and it is much faster than invoking the Ansible runtime, playbook, roles, and variables we would have been using before.
Is it really simpler? More elegant?

Let's take a closer look at the Mise declarations.

### Declarations: Bootstrap

First of all, what do we need to declare for the bootstrapped environment to be able to run our application?
This is [documented](https://docs.getindico.io/en/latest/installation/production/deb/nginx/#install-packages) by the application itself -- it expresses system-level packages which are required, which users should be present with which permissions, and even which processes should be started, should this be run inside a systemd-enabled environment[^actual_deps].

Our bootstrap declaration tries to reproduce this:

First we declare system-level packages:

{% highlight toml %}
[bootstrap.packages]
"apt:libpq-dev" = "16.15-0ubuntu0.24.04.1"
"apt:gcc" = "latest"
"apt:git" = "latest"
"apt:libglib" = "2.0-0t64"
{% endhighlight %}


User and groups are taken from [github.com/indico/indico-containers](# https://github.com/indico/indico-containers/blob/master/indico-prod/worker/Dockerfile) repo:
{% highlight toml %}
[bootstrap.groups.indico]
system = false
gid = 999

[bootstrap.users.indico]
system = false
uid = 999
group = "indico"
groups = ["indico"]
home = "/home/indico"
shell = "/bin/bash"
create_home = true
{% endhighlight %}

We also provision a target for where the application will be deployed into:

{% highlight toml %}
[bootstrap.directories."/opt/indico"]
owner = "indico"
group = "indico"
mode = "0755"
{% endhighlight %}

This might look a bit strange at first glance -- where does `/tmp/mise.indico.toml` come from?
It was provisioned into the image by Packer previously - Mise will find it and ensure that it's put into application's deployment target with the correct permissions, as part of the bootstrap process.

{% highlight toml %}
[bootstrap.files."/opt/indico/mise.toml"]
source = "/tmp/mise.indico.toml"
owner = "indico"
group = "indico"
mode = "0644"
{% endhighlight %}

We could have used a `content` argument instead of a `source`, but that would have made our bootstrap declaration a bit messy.

It also means that we can independently maintain a single definition for our application's environment, which we can re-use both on our development environment as well as on the production envrionment.

[_Plus ca change, plus ca reste la meme chose_.](https://12factor.net/dev-prod-parity)

### Declarations: Application

The application's environment definition is as follows:

{% highlight toml %}
[tools]
python = { version = "3.12" }
uv = "0.12.13"

[env]
# Automatic virtualenv activation
_.python.venv = {
    path = "/opt/indico/.venv",
    create = true,
    uv_create_args = ["--seed"]
}

[settings]
python.uv_venv_auto = "create|source"
activate_shims = true
auto_install = true

[tasks.install]
description = "Install dependencies"
alias = "i"
run = "uv pip install -r requirements.txt"

{% endhighlight %}

This single file:

1. Declares the Python runtime
2. Manages the virtualenv
3. Provisions dependencies with `uv`

It can also be extended with other tasks, to fully describe what the application does.
Indico for example runs a Celery worker in some cases, or starts the server as UWSGI application _etc_.
These can all be encoded into the application's declaration.

Put another way, `mise.indico.toml` not only declares what the application _needs_, but also what it _does_.

## Discussion

Let's take a step back.
We have four files:

1. Packer template
2. Mise bootstrap declaration
3. Mise application declaration
4. Application dependency list

Inside the Packer template we have 3 file provisioners and two script provisioners.

It is:

* Maintainable. It's not entirely clear to me whether dependency checkers will be able to catch updates to my system dependencies -- I may need to maintain a list of system packages that Renovate can understand.
But it will certainly be able to handle updates to the application ecosystem in `requirements.txt`.
* **Fast**. The whole workflow takes only one command from text to registry: `packer build`.
The provisioners are _fast_ because the tools running inside them -- `mise` and `uv` -- are Rust.
* **Reliable**. The _same_ environment is provisioned by Mise on the development environment as on the production artifact.
* **Elegant**. Nothing else is needed -- I have eliminated the need for a python runtime to handle Ansible for me.
The bootstrap declaration is well-structured and just a few lines.
The application declaration contains only what is required.

**Mise killed Ansible.**

---

## Footnotes and references

[^thisblog]: I actually recently pulled it into this very blog.
[^actual_deps]: These always have to be interrogated. The documentation makes assumptions about the user who is reading it, what they intend on doing, and what the context is. From the indico documentation, this seems like the authors assume that the application is being deployed into a static, persistent environment, not an ephemeral one like ours.
