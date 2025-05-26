---
layout: post
title: A crappy home-made backup operator
date: 2024-07-01 07:00 +0100
headline: Averting disaster.
categories:
  - blog
tags:
  - nomad
  - consul
  - terraform
  - cloudflare
mermaid: true
---

Hashi At Home is a Vault, Consul and Nomad cluster, deployed on a set of fairly cheap hardware.
It's fairly easy to create this setup, so let's not claim anything of particular importance, but they chief importance of this work is that it is **at home** -- _my_ home.

I personally really care about the data in this platform, so I want to make sure that it is backed up to a safe place regularly.
In the event of a disaster, for example, a fire, or a theft, I need to be able to take arbitrary hardware, even a cloud setup somewhere, and restore my data to a running environment.

I will cover the bootstrapping process in a later post, but in this post, I want to cover the backup process, and decisions involved therein.

## Where to backup to

Assuming we can easily execute a backup procedure, we need to first acknowledge that we have not addressed a fundamental question: **where** to backup to.
The backup location needs to be both safe and accessible.
These requirements are famously at odds, since a perfectly safe location is inaccessible to actors both malicious and benign.
A perfectly accessible location on the other hand may be accessible to actors which we would like to exclude, exposing our precious data to tampering or worse.

We also need  a location which is physically separate from the environment that Hashi@Home is deployed in (_i.e._ my home office) -- "off-site" in the parlance, if you will.

The options I had come up with initially were the following:

1. Backup to an attached external USB drive.
1. Backup to a bucket on a cloud provider

### External attached storage

In the first case, it would have been fairly simple to leave the USB drive attached to one of the nodes of the machine, and schedule the backup job to run on that node, dumping backups to the path that the drive is mounted on.
However, there are obvious drawbacks to this approach which make it unfeasible even in fairly common scenarios.
First of all, if there was a fire or theft, the drive would probably be lost along with the rest of the hardware.
Secondly, and less dramatically, if the node which the drive were attached to were to fail somehow, the backup process would also fail.
So even though I would have the data within my personal control at all times, this approach simply would not provide the protection and reliability that I need.

### Cloud storage

The second  option was to write the backup data to a bucket on a cloud provider.
This immediately introduces a set of aspects to consider:

- **Cost**: would the long-term storage of the backup data be negligible?
- **Security**: can the cloud provider store my data securely so that only Hashi@Home can write updates and read backed-up data?
- **Overhead**: would I need to have a contract or similar relationship with a new entity just to store my backup data?


## Choosing Cloudflare R2

Given that the local USB storage option is ruled out, I chose Cloudflare R2 as the destination for my backups.
Cloudflare R2 pricing for the [free tier](https://developers.cloudflare.com/r2/pricing/#free-tier) provides 10 GB-month / month for free.
Given that a snapshot of all 3 services (Vault, Consul and Nomad) is under 100MB, I would be able to write 100 of these backups a month or about 3 a day -- morning noon and night.
From a pricing point of view then, R2 gets off to a good start[^alternatives], and since I already use Cloudflare for DNS and worker functions in a range of other scenarios, it passes the "overhead" filter as well as the "cost" filter.
When it comes to the "security" aspect, I will have to just trust [Cloudflare's R2 security](https://developers.cloudflare.com/r2/reference/data-security/) which provides encryption at rest and in transit, as well as several 9's of durability.

Now that we have chosen a location for the data, we can proceed to actually implement the backup process.

## Backup procedure implementation

Consul, Vault and Nomad all have built-in snapshot capabilities, which essentially export a snapshot of the Raft state.
Creation of a snapshot -- a synonym for backup -- is started via a call to the respective REST API endpoints:

* **Vault**: [`GET /sys/storage/raft/snapshot`](https://developer.hashicorp.com/vault/api-docs/system/storage/raft#take-a-snapshot-of-the-raft-cluster)
* **Consul**: [`GET /snapshot`](https://developer.hashicorp.com/consul/api-docs/snapshot#generate-snapshot)
* **Nomad**: [`GET /v1/operator/snapshot`](https://developer.hashicorp.com/nomad/api-docs/operator/snapshot#generate-snapshot)

Each of these calls requires an authentication token for the relevant service passed as the headers `X-Vault-Token`, `X-Consul-Token` and `X-Nomad-Token` respectively for Vault, Consul and Nomad.
The generated snapshot is then written to a file which eventually needs to be placed into the persistent off-site storage.

### Secrets Side Quest

These tokens are "secrets", and are typically available from the secrets store (_i.e._ Vault) with a relevant authentication token.
This is often a Catch-22, where you need a token to get a token!
The solution to this comes via the AppRole authentication mechanism which can issue a Vault token with specific roles tied to policies which allow only issuing of Vault, Consul and Nomad tokens.
In particular, the Vault token should allow reading the snapshot path, but also create Nomad and Consul tokens with _their_ particular ACLs.
When the process running the backup is launched, it should be provided with the vault token via AppRole, and then use that token both to interact directly with Vault, as well as retrieve the Consul and Nomad tokens.

### Storing the snapshots

The simplest way to do this would be to use an S3 client such as `rclone` as [suggested by Cloudflare](https://developers.cloudflare.com/r2/examples/rclone/) to put the snapshot into a bucket for later use during a recovery operation.
In order to maintain a timeseries, the snapshots are created with a filename including the timestamp of the operation, so that the latest snapshot would be the one with the "biggest" filename sorted numerically.

## Implementations

This general approach was implemented a few times in essentially two different ways, and with a [third](#better-use-of-apis) which is coming to mind as I write this.
The first was to write an Ansible playbook, while the second was to write a small Go application.

These approaches have pros and cons, and are influenced by a set of tradeoffs, some objective, some more subjective to my experience, which perhaps it's worth while to take a deeper look into that.
Let's start with the Ansible approach.


### Ansible implementation

The Ansible implementation has the following tradeoffs:

* Pros
  1. A single playbook can be written encoding the full procedure.
  1. The playbook is human-readable
  1. Access to the necessary secrets can be done via the Ansible lookup for Vault (with initial vault token with necessary roles)
* Cons
  1. Requires Ansible and dependencies -- _i.e._ python runtime and virtualenv

This is clearly very easy to implement:

{% highlight yaml %}
{% raw %}
---
- name: Backup State
  hosts: localhost
  vars:
    services:
      - name: vault
        endpoint: "{{ lookup('env', 'VAULT_ADDR') }}/v1/sys/storage/raft/snapshot"
        headers:
          X-Vault-Token: "{{ lookup('env', 'VAULT_TOKEN') }}"
      - name: consul
        endpoint: "{{ lookup('env', 'CONSUL_HTTP_ADDR') }}/v1/snapshot"
        headers:
          X-Consul-Token: "{{ lookup('env', 'CONSUL_HTTP_TOKEN') }}"
      - name: nomad
        endpoint: "{{ lookup('env', 'NOMAD_ADDR') }}/v1/operator/snapshot"
        headers:
          X-Nomad-Token: "{{ lookup('env', 'NOMAD_TOKEN') }}"

  tasks:
    - name: Get Cloudflare Secret
      community.hashi_vault.vault_kv2_get:
        engine_mount_point: cloudflare
        path: hah_state_backup
        url: "{{ lookup('env', 'VAULT_ADDR') }}"
        token: "{{ lookup('env', 'VAULT_TOKEN') }}"
        token_validate: true
      register: r2

    - name: Start the clock
      ansible.builtin.set_fact:
        time_now: "{{ ansible_date_time.epoch }}"


    - name: Create Snapshot
      ansible.builtin.uri:
        method: GET
        url: "{{ item.endpoint }}"
        dest: "{{ lookup('env', 'PWD') }}/{{ item.name }}-backup-{{ time_now }}.snap"
        mode: "0644"
        return_content: true
        headers: "{{ item.headers }}"
      loop: "{{ services }}"

    - name: Store Snapshots
      amazon.aws.s3_object:
        bucket: hah-snapshots
        endpoint_url: "{{ r2.data.data.s3_endpoint }}"
        mode: put
        object: "{{ item.name }}/{{ item.name }}-backup-{{ now }}.snap"
        secret_key: "{{ r2.data.data.secret_key }}"
        access_key: "{{ r2.data.data.access_key_id }}"
        src: "{{ lookup('env', 'PWD') }}/{{ item.name }}-backup-{{ time_now }}.snap"
      loop: "{{ services }}"

    - name: Cleanup snapshots
      ansible.builtin.file:
        name: "{{ item.name }}-backup-{{ time_now }}.snap"
        state: absent
      loop: "{{ services }}"
{% endraw %}
{% endhighlight %}

There are only two real actions:

1. Make the snapshot
1. Store the snapshot

but as described above, other tasks are necessary to retrieve secrets in order to interact with the services, including the R2 bucket in Cloudflare where the snapshots will reside.

The simplicity of this task puts the downside of the approach into quite stark relief -- A full python runtime, along with several python packages for the Ansible lookup plugins and S3 interactions is required.
This results in several hundred MB of runtime, several seconds execution time  for essentially a few HTTP calls.

Maybe we could make something a bit more stand-alone and smaller?

### Go application implementation

This consideration led me to implementing the workflow via a standalone application instead of via a framework like Ansible.
I ruled out Python for the same reason I ruled out Ansible: I would have to pull in a python runtime and dependencies which would be essentially the same as first approach.
However, I suspected that I could write a standalone executable for arbitrary environments with Go.

Here is an analysis of where I stand regarding pros and cons for the Go implementation:

* Pros
  1. Compiled to executable artifact - easier to version, package, distribute and verify integrity
  1. No runtime dependencies
  1. Concurrent execution
  1. SDKs for all the services are available[^HashiSDKs]
* Cons
  1. Requires understanding and competency with the Go language

Now, the downside here is very subjective, because I am _learning_ Go and have been for the past 3-4 years, so it's currently not easy for me to develop even simple and small applications.
However, this is also an upside, because with a specific problem to solve, I also have a good motivation to learn and apply techniques in Go, and this is probably the simplest thing that actually provides value.
It's only a few HTTP calls after all!
The performance is also more or less guaranteed to better because it's a single binary, but also because of Go's built-in [concurrency](https://go.dev/wiki/LearnConcurrency).

While I can show the implementation in Ansible because I have already finished it and was using it in "production" (lol), the Go implementation is still a work in progress.
Given the pros and cons above, I consider it a more elegant approach for long-term use, since as an operator, it could expose control functions[^control_functions] and telemetry[^telemetry] as HTTP paths, whereas the Ansible implementation is a batch execution plain and simple.

### Better use of APIs

Astute readers will notice in the Ansible implementation that there is 2-step process whereby first a snapshot is generated and written to disk, and is then subsequently read from disk and posted to the S3 endpoint.
This presents a small risk of interception or corruption of data, since who or whatever compromises the persistent storage can compromise the snapshot.
If the snapshot were kept in memory it's a bit harder to attack it, or rather there is a very different vector.
Furthermore, Cloudflare has a [Go SDK](https://github.com/cloudflare/cloudflare-go) which would allow native use of their APIs rather than the generic S3 interface.
There's lots to learn and improve upon here!

## Scheduling the backups

Whether it's by Ansible or by Go, I still need a way to actually _execute_ the backup procedure.
One choice might be to have a systemd timer running somewhere, but what if I can't guarantee that that particular computatom is available at the scheduled time?
A better approach would be to take advantage of a distributed scheduler, for example Nomad itself!

We could define a [periodic batch](https://developer.hashicorp.com/nomad/docs/schedulers#batch) job to place and execute the procedure.
As such, it could be scheduled anywhere that satisfies the job's constraints, _i.e._ provides the relevant runtime requirements.
Essentially this boils down to an agent which can request a Vault token with the correct role, since the rest of the runtime (python + Ansible in the case of Ansible) can be provisioned by pre-start tasks or artifacts provisioned into the execution environment.

### A Nomad job to backup Nomad on your Nomad

The job specification looks a lot like this:

{% highlight hcl %}
{% raw %}
job "backup" {
  datacenters = ["dc1"]
  type = "batch" # Specify a batch job with a periodic execution
  periodic {
    crons = ["*/10 * * * * *"] # RPO of 10 minutes ago
    prohibit_overlap = true # Run only one at a time, if for some reason an execution takes more than the interval between executions
  }

  group "hah" {
    count = 1

    task "scheduled" {
      driver = "docker" # We run in an alpine container which we'll provision accordingly.
      config {
        image = "alpine:3.20.1"
        entrypoint = ["/local/run.sh"] # This is templated below
      }
      # This template creates the environment variables with Vault Template necessary
      # for Ansible to authenticate via lookup plugins to the Vault, Consul and Nomad APIs
      template {
        data        = <<-EOH
CONSUL_HTTP_ADDR=http://localhost:8500 # There's always an Consul agent running on a Nomad client
# We create a Consul token with the relevant role by reading the the Vault Consul Secrets Engine mount
CONSUL_HTTP_TOKEN="{{ with secret "hashi_at_home/creds/cluster-role" }}{{ .Data.token }}{{ end }}"
# The github token is used to authenticate to the Github API so that we can get artifacts from a private repo later.
# Pretty radical that this is a one-time token generated on demand by the Vault plugin.
GITHUB_TOKEN="{{ with secret "/github_personal_tokens/token"  "repositories=personal-automation"
"installation_id=44668070"}}{{ .Data.token }}{{ end }}"
# This queries the Consul catalogue and gives me the first instance of a Nomad server.
# It could have alternatively been http://nomad.service.consul, but I would still have to look up the port
NOMAD_ADDR={{ with service "http.nomad" }}{{ with index . 0 }}http://{{ .Address }}:{{ .Port }}{{ end }}{{ end }}
# Same as with Consul token, we request a Nomad token from vault on the relevant mount (nomad)
# with the relevant ACL set (mgmt)
NOMAD_TOKEN="{{ with secret "nomad/creds/mgmt" }}{{ .Data.secret_id }}{{ end }}"
# Same as with the Nomad API, we look it up from Consul.
VAULT_ADDR={{ range service "vault" }}http://{{ .Address }}:{{ .Port }}{{- end }}
      EOH
        destination = "${NOMAD_SECRETS_DIR}/env"
        perms       = "400"
        env = true
      }

      # This template provisions python, ansible and dependencies
      template {
        data = <<EOT
#!/bin/sh
source ${NOMAD_SECRETS_DIR}/env
apk add python3 py3-pip
apk add ansible
ansible-playbook --version
# Get the playbook from my private repo - we need the github token for this.
curl -X GET \
  -H "Accept: applicaton/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-Github-Api-Version: 2022-11-28" \
  https://api.github.com/repos/brucellino/personal-automation/contents/playbooks/backup-state.yml \
  | jq -r .content \
  | base64 -d > playbook.yml
ansible-playbook -c local -i localhost, playbook.yml
        EOT
        destination = "/local/run.sh"
        perms = "0777"
      }

      logs {
        max_files     = 10
        max_file_size = 10
      }

      # The job needs to authenticate to Vault in order to be issued a token.
      identity {
        env  = true
        file = true
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
      }
    }
  }
}
{% endraw %}
{% endhighlight %}

## Conclusion

The Ansible implementation works ok, but is ugly, inelegant, and hasn't taught me anything.
Nevertheless, I am assured of having recent snapshots of my cluster in this primitive way, something which came in handy recently when I tried to replace a consul server with a different one and ended up having to perform a restore!

In the next episode, if there ever is one, I'll tell a story about how I made a small Nomad operator with Go to backup state.

✌️ Written by Bruce, not AI.

---
## Footnotes and References

[^alternatives]: I have not done much research comparing this pricing to alternatives like AWS S3 or Google Cloud Storage. This would be interesting, but since R2 passes the cost filter, I decided to simply forge ahead.
[^HashiSDKs]: [Vault](https://pkg.go.dev/github.com/hashicorp/vault/api) and [Consul](https://pkg.go.dev/github.com/hashicorp/consul/api) have versioned API SDKs in Go, but [Nomad's](https://pkg.go.dev/github.com/hashicorp/nomad/api) does not yet have semantic versions, making the interface somewhat unstable.
[^control_functions]: Control functions here refer to affordances which allow one to control (in the plain meaning of the word) the operator. This could expose a path for making a snapshot now, locking state while making snapshots, checking integrity of snapshots, automatically cleaning up stale snapshots, _etc_.
[^telemetry]: This refers to the ability to observe the performance of the procedures -- how fast are backups being processed, how much storage is being used, what percentage of backups fail, _etc_.
