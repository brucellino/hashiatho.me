---
layout: post
title: Vault Storage
date: 2021-12-31 12:00 +0100
headline: Moving Vault Storage
categories:
  - blog
tags:
  - vault
  - consul
---

Vault was the the first component of Hashi@home, the keys to the castle if you will.
As such, I configured it as simply as possible, just to get  something up and running.
It is a testament to the quality of the software that the simple file-backed single instance worked for months without a hitch.

Once I had become comfortable with operating Vault and started using it to store actual secrets in it, murmurs of anxiety began to creep up on me.
After all, the SD card I'm using to run the raspberry pi on isn't the most reliable bit of hardware out there!
And so it was that I began to explore the various [Vault storage backends](https://www.vaultproject.io/docs/configuration/storage)

## Options

In the spirit of Hashi@Home, I wanted to select the option which reduced the tool surface area.
Of the options available at the time (mid-late 2020, or Vault 1.4.x), the only ones which seemed valid were [Consul](https://www.vaultproject.io/docs/configuration/storage/consul) and [S3](https://vaultproject.io/docs/configuration/storage/s3).
The others either required forking out some cash, or introduced an unacceptable technology overhead.
Between the two options, it seemed clear to me that Consul was the better option, since it was already running locally, an integrated part of the Hashi stack and of course free of cost.

The consul backend was duly enabled and _voilà_ Vault was now storing secrets in the Consul KV store.

<figure>
  <img src="/assets/img/Screenshot%202021-12-31%20at%2013-28-22%20Key%20Value%20-%20Consul.png" />
  <figcaption>
  Snapshot of Vault KV store in Consul, taken from the Consul UI.
  </figcaption>
</figure>

## Integrated storage

Starting in [version 1.4](https://github.com/hashicorp/vault/blob/main/CHANGELOG.md#140), Vault supports [integrated storage](https://www.vaultproject.io/docs/configuration/storage/raft) using the Raft protocol.
This represented a significant improvement from my point of view, because it removes the chicken-and-egg problem of which service to start first, Consul or Vault.
Vault could be self-consistently deployed by itself in high-availability mode, across several of the computatoms.
Indeed, this seemed like the perfect use case for the several pi zeros I had, since there is no Nomad client support for them, so what better use for them than to act as the voters in the Vault quorum?

Apart from the reduction in complexity by using the integrated storage, further benefits include the increased resilience of the service against machine outages, thanks to the HA configuration.
The migration also gives me the ability to declare the Vault storage in Consul.

## Fault tolerance

As it turns out, the three of the pi-zeros are attached to separate USB hubs. Yes, the power still comes through the central AC to the house, but at least I could turn them on and off independently, via the USB hub power switch.
It would be a nice way to demonstrate fault tolerance.

## Applying the upgrade

Since I wanted Vault to have zero platform dependencies, it would be defined as as an Ansible playbook.
The first thing to do is to declare a new group in the inventory: `vault_servers`, which would include all pi-zeros and the Raspberry Pi 4 currently hosting the Sense HAT.
The first to do would be to make a snapshot of the Vault data in order to provide a backup in case of disaster.
Once this was done, I could apply the new configuration, via an Ansible template task in the role:

{% highlight hcl %}
storage "raft" {
 path = "/vault/raft"
 node_id = "{{ ansible_hostname }}"
 retry_join {
   leader_tls_servername   = "sense.station"
   leader_api_addr         = "http://192.168.1.16:8200"
{% if tls_enabled %}
   leader_ca_cert_file     = "/opt/vault/tls/vault-ca.pem"
   leader_client_cert_file = "/opt/vault/tls/vault-cert.pem"
   leader_client_key_file  = "/opt/vault/tls/vault-key.pem"
{% endif %}
 }
}

listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable=true
}

listener "tcp" {
  address = "{{ ansible_default_ip }}:8200"
{% if tls_enabled %}
  tls_cert_file      = "/opt/vault/tls/vault-cert.pem"
  tls_key_file       = "/opt/vault/tls/vault-key.pem"
  tls_client_ca_file = "/opt/vault/tls/vault-ca.pem"
{% else %}
  tls_disable = true
{% endif %}
}

api_addr = "http://{{ ansible_hostname }}:8200"
cluster_addr = "http://{{ ansible_hostname }}:8201"
service_registration "consul" {
  address = "127.0.0.1:8500"
  service = "vault"
  check_timeout = "10s"
}

{% endhighlight %}

Since we do not assume the presence of Consul on the hosts, we cannot use a Consul template to deliver the Vault configuration, and have to deliver it with an Ansible playbook run, which would install the desired version of Vault, systemd units and raft storage destinations, as well as the templated configuration file.

## Joining and Unsealing new raft members

Shown in the Vault configuration template is a hardcoded leader address, the Raspberry PI4, `sense`.
This configuration is a bit of a special case, since I had decided that this machine would be the Vault leader _a-priori_.
There would therefore not necessarily be a leader election for the Raft storage initially, but the new raft members would join this existing one.

Upon start of the service on _e.g._ the pizero mounted on the wall (`wallpi`), we see the following in the Vault log, confirming the retry join of the raft cluster:

{% highlight none %}
==> Vault server configuration:

             Api Address: http://wallpi.station:8200
                     Cgo: disabled
         Cluster Address: https://wallpi.station:8201
              Go Version: go1.17.5
              Listener 1: tcp (addr: "127.0.0.1:8200", cluster address: "127.0.0.1:8201", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")
              Listener 2: tcp (addr: "192.168.1.11:8200", cluster address: "192.168.1.11:8201", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")
               Log Level: info
                   Mlock: supported: true, enabled: true
           Recovery Mode: false
                 Storage: raft (HA available)
                 Version: Vault v1.9.2
             Version Sha: f4c6d873e2767c0d6853b5d9ffc77b0d297bfbdf

==> Vault server started! Log data will stream in below:

2022-01-02T07:30:10.948+0100 [INFO]  proxy environment: http_proxy="\"\"" https_proxy="\"\"" no_proxy="\"\""
2022-01-02T07:30:12.094+0100 [INFO]  core: Initializing VersionTimestamps for core
2022-01-02T07:30:12.247+0100 [INFO]  core: raft retry join initiated

{% endhighlight %}

At this point, the vault is still sealed:

{% highlight none %}

VAULT_ADDR=http://localhost:8200 vault status
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       5
Threshold          3
Unseal Progress    0/3
Unseal Nonce       n/a
Version            1.9.2
Storage Type       raft
HA Enabled         true

{% endhighlight %}

Using the unseal tokens from the instance running on the Sense HAT machine, I unseal the service when it comes up:

{% highlight none %}

2022-01-02T08:07:31.483+0100 [INFO]  core: security barrier not initialized
2022-01-02T08:07:31.484+0100 [INFO]  core: attempting to join possible raft leader node: leader_addr=http://192.168.1.16:8200
2022-01-02T08:07:31.515+0100 [WARN]  core: join attempt failed: error="waiting for unseal keys to be supplied"
2022-01-02T08:07:31.515+0100 [ERROR] core: failed to retry join raft cluster: retry=2s
2022-01-02T08:07:32.253+0100 [INFO]  core: security barrier not initialized
2022-01-02T08:07:32.254+0100 [INFO]  core: waiting for raft retry join process to complete
2022-01-02T08:07:33.516+0100 [INFO]  core: security barrier not initialized
2022-01-02T08:07:33.517+0100 [INFO]  core: attempting to join possible raft leader node: leader_addr=http://192.168.1.16:8200
2022-01-02T08:07:33.615+0100 [INFO]  core.cluster-listener.tcp: starting listener: listener_address=127.0.0.1:8201
2022-01-02T08:07:33.620+0100 [INFO]  core.cluster-listener.tcp: starting listener: listener_address=192.168.1.11:8201
2022-01-02T08:07:33.621+0100 [INFO]  core.cluster-listener: serving cluster requests: cluster_listen_address=127.0.0.1:8201
2022-01-02T08:07:33.622+0100 [INFO]  core.cluster-listener: serving cluster requests: cluster_listen_address=192.168.1.11:8201
2022-01-02T08:07:33.641+0100 [INFO]  storage.raft: creating Raft: config="&raft.Config{ProtocolVersion:3, HeartbeatTimeout:5000000000, ElectionTimeout:5000000000, CommitTimeout:50000000, MaxAppendEntries:64, BatchApplyCh:true, ShutdownOnRemove:true, TrailingLogs:0x2800, SnapshotInterval:120000000000, SnapshotThreshold:0x2000, LeaderLeaseTimeout:2500000000, LocalID:\"wallpi\", NotifyCh:(chan<- bool)(0x9052820), LogOutput:io.Writer(nil), LogLevel:\"DEBUG\", Logger:(*hclog.interceptLogger)(0x9066af8), NoSnapshotRestoreOnStart:true, skipStartup:false}"
2022-01-02T08:07:33.647+0100 [INFO]  storage.raft: initial configuration: index=1 servers="[{Suffrage:Voter ID:sense Address:192.168.1.16:8201} {Suffrage:Voter ID:frontpi Address:frontpi.station:8201} {Suffrage:Nonvoter ID:wallpi Address:wallpi.station:8201}]"
2022-01-02T08:07:33.662+0100 [INFO]  core: successfully joined the raft cluster: leader_addr=http://192.168.1.16:8200
2022-01-02T08:07:33.664+0100 [INFO]  core: security barrier not initialized
2022-01-02T08:07:33.665+0100 [INFO]  storage.raft: entering follower state: follower="Node at wallpi.station:8201 [Follower]" leader=
2022-01-02T08:07:35.587+0100 [WARN]  storage.raft: failed to get previous log: previous-index=173384 last-index=1 error="log not found"
2022-01-02T08:07:35.619+0100 [INFO]  storage.raft.snapshot: creating new snapshot: path=/vault/raft/raft/snapshots/102-173384-1641107255619.tmp
2022-01-02T08:07:37.333+0100 [INFO]  storage.raft: copied to local snapshot: bytes=374858
2022-01-02T08:07:37.338+0100 [INFO]  storage.raft.fsm: installing snapshot to FSM
2022-01-02T08:07:37.371+0100 [INFO]  storage.raft.fsm: snapshot installed
2022-01-02T08:07:37.483+0100 [INFO]  storage.raft: Installed remote snapshot
2022-01-02T08:07:37.774+0100 [WARN]  core: cluster listener is already started
2022-01-02T08:07:37.777+0100 [INFO]  core: vault is unsealed
2022-01-02T08:07:37.777+0100 [WARN]  service_registration.consul: concurrent initalize state change notify dropped
2022-01-02T08:07:37.801+0100 [INFO]  core: entering standby mode
2022-01-02T08:07:42.028+0100 [WARN]  storage.raft: skipping application of old log: index=173384

{% endhighlight %}

At this point, we can see that the new node in the raft cluster:

<figure>
  <img src="/assets/img/Screenshot%202022-01-02%20at%2008-10-00%20Vault.png">
  <figcaption>Wallpi has join the chat</figcaption>
</figure>

## Next steps

Now that we have the cluster up and secrets in storage replicated across a Raft cluster, we have a somewhat more resilient and reliable setup.
The desired effect would be that even if the beefy leader went down, we would still be able to access our secrets via the other nodes, discovering them with the Consul DNS interface.
This is not 100% foolproof though; to protect from true data loss and not just a temporary outage, we need to make backups of raft snapshots to be able to restore from a known state in the case of disaster.

Other steps would be to enable TLS for the listeners, using the Vault CA, which will be described in a future post.

For now, let us merely celebrate this small win and tell ourselves a small secret:

`vault kv put kv/secret epic_win=true`
