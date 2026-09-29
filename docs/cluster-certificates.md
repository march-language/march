---
layout: docs
title: Cluster Certificates
nav_order: 10.55
permalink: /docs/cluster-certificates/
---

# Cluster Certificates

A March cluster can admit nodes by **certificate** instead of by one shared
secret. Each node gets its own ed25519 key and a certificate for that key,
signed by an **operator key** you keep offline. A node joins only if its
certificate verifies under the operator key, has not expired and has not been
revoked. A leaked certificate or key affects one node, and you can revoke it
without rotating anything else.

This page is the operator's guide: making keys, issuing and renewing
certificates, configuring nodes, and revoking. How the handshake and the
per-frame MAC work is in [Clustering]({{ site.baseurl }}/docs/clustering/#authentication--handshake).

## What you get, and what you don't

- **Who may join.** Only nodes holding a certificate from your operator key.
  A node cannot claim another node's name: the certificate names it, and the
  node proves in every handshake that it holds the certificate's key.
- **Frame integrity.** Every frame after the handshake carries a MAC. A frame
  changed, injected or replayed on the wire is dropped and counted.
- **Expiry and revocation.** A peer is disconnected when its certificate
  expires or is revoked, and is reported as `NodeDead(_, "certificate
  expired")` or `NodeDead(_, "certificate revoked")`.
- **Not encryption.** Frames are readable by anyone on the network path. Run
  the cluster on a private network, or under a service mesh that encrypts.
  Node names are SPIFFE-style URIs so that a mesh can carry the same
  identities.
- **Not yet: role enforcement.** A certificate lists the protocol roles a node
  may offer or initiate and whether it may use raw sends. Nodes can read those
  fields (`ClusterNode.peer_cert`), but nothing refuses an offer or a send on
  their basis yet.

## 1. Make the operator key

```bash
forge cluster keygen --out ./pki
```

This writes `pki/operator.key` (the secret key, hex, mode 0600) and
`pki/operator.pub` (the public key, hex), and prints the line to give every
node:

```
MARCH_CLUSTER_OPERATOR_PUBKEY=3d5b4133b0c5f733...
```

Keep `operator.key` off the nodes: whoever holds it can issue certificates
and revocations. It is a different key from the one `forge hot-reload keygen`
makes for signing deploys, on purpose. `keygen` refuses to overwrite an
existing `operator.key` unless you pass `--force`, because replacing it
invalidates every certificate it signed.

## 2. Issue a certificate per node

```bash
forge cluster cert web-1 \
  --roles Checkout.Ledger:offer,Checkout.Client:initiate \
  --flags raw_send \
  --days 30 \
  --trust-domain prod.example --pool web \
  --operator-key ./pki/operator.key --out ./pki
```

This writes `pki/web-1.key` (the node's secret key, mode 0600) and
`pki/web-1.cert`, and prints the certificate's URI, serial and expiry:

```
node spiffe://prod.example/pool/web/node/web-1
serial 9944755218842a7914166be67a8bc8da
not_after 1792849214 (unix seconds)
```

- `NODE` must be the node's `MARCH_NODE_NAME`: the handshake checks that the
  certificate names the node that presents it.
- `--roles` takes `Proto.Role:offer` and `Proto.Role:initiate`; anything else
  is refused.
- `--days` defaults to 90. `--seconds` sets a short life (tests, or very
  short-lived certificates reissued by automation).
- Keep the serial: a revocation of this one certificate names it.

## 3. Configure the nodes

Each node needs its key, its certificate and the operator public key:

```bash
MARCH_NODE_NAME=web-1
MARCH_NODE_PORT=4001
MARCH_CLUSTER_NODES=10.0.0.2:4001
MARCH_NODE_KEY=/run/secrets/web-1.key
MARCH_NODE_CERT=/run/secrets/web-1.cert
MARCH_CLUSTER_OPERATOR_PUBKEY=/run/secrets/operator.pub
```

Each of the three may hold the value itself or name a file holding it. With
`MARCH_NODE_CERT` set, `ClusterNode.config_from_env` uses certificate mode and
ignores `MARCH_CLUSTER_SECRET`. At startup the node checks its own certificate:
it must verify under the operator key, be unexpired, name `MARCH_NODE_NAME`,
and name the key in `MARCH_NODE_KEY`. A misconfigured node stops with the
reason instead of failing every handshake later.

Every node of a cluster must run in the same mode. A certificate node refuses
a shared-secret node and the other way round, with a message naming the
variables to set, so move a cluster to certificates all at once rather than one
node at a time.

## 4. Renew before expiry, without a restart

A certificate is checked in every handshake and rechecked on every tick. When
it expires, its peers disconnect the node. Before that, issue a new
certificate and put it where the node reads it. The node replaces its
certificate while it runs: there is no restart, and the node's links and the
sessions on them stay up.

```bash
forge cluster cert web-1 --node-key ./pki/web-1.key --days 30 \
  --roles ... --operator-key ./pki/operator.key --out ./pki
```

`--node-key` reuses the node's existing key, so only `web-1.cert` changes.
Copy it over the file `MARCH_NODE_CERT` names on the node. The node re-reads
that file (and `MARCH_NODE_KEY`'s, when the key is a file) every
`MARCH_NODE_CERT_POLL_MS` milliseconds, 10 s by default, and takes the new
certificate once it:

- verifies under the operator key and has not expired,
- names this node (`MARCH_NODE_NAME`) and the node's key,
- has not been revoked.

Otherwise the node keeps the certificate it has and reports why (below). This
is the usual path for a Kubernetes secret volume, cert-manager, a Vault agent
or a CI job copying files: they rewrite the file and signal no one, so the
node watches the file rather than waiting for a signal.

To change the key as well, leave out `--node-key`. `forge cluster cert` then
makes a new key, and you replace both files. Write the key first: until the
certificate that names it arrives, the node refuses the pair and keeps the old
one.

Code that manages certificates itself can call the same replacement directly:

```march
match ClusterNode.replace_cert(node, cert_text, "") do     -- "" keeps the key
  Ok(c) -> println("now serving " ++ c.serial)
  Err(e) -> println("certificate refused: " ++ e)
end
```

The second argument is a new key in hex, for a certificate that names one.

What happens on the wire. New handshakes present the new certificate at
once. Links already up are not redialled, because a new connection would
cancel every session on the old one. Instead the node sends each linked peer
the new certificate over the existing, authenticated link, with a signature
made by the certificate's own key to prove it holds that key. The peer checks
it as it would in a handshake, including that it names the same node. From
then on it holds that certificate for the link: the expiry recheck, revocation
and `peer_cert` all use the new one, so the link outlives the old
certificate's expiry. After that expiry nobody can join with the old
certificate. A peer running a March from before live replacement ignores the
update and drops the link when the old certificate expires. The node redials
it at once under the new certificate, but sessions on that link are lost.
`run_<Role>` direct connections read the environment's files at every
connect, so they present the new certificate from their next connection.

Revoke the old certificate's serial once the new one is in place if it must
stop working before it expires.

## 5. Revoke

To cut off one certificate (a node was compromised, or decommissioned early):

```bash
forge cluster revoke --serial 9944755218842a7914166be67a8bc8da --operator-key ./pki/operator.key
```

To cut off every certificate of a node:

```bash
forge cluster revoke --node web-1 --trust-domain prod.example --pool web --operator-key ./pki/operator.key
```

Either prints a token. Give it to any running node:

```march
match ClusterNode.revoke(node, token) do
  Ok(_) -> ()
  Err(e) -> println("revoke refused: " ++ e)
end
```

The node passes it on to every peer, and each drops links to the revoked
certificate and refuses its handshakes. A node started later learns it from
its peers when it links, or from `MARCH_CLUSTER_REVOCATIONS` (tokens separated
by commas or whitespace, or a file of them), so add the token there too.
`ClusterNode.revocations(node)` lists what a node knows. A token counts only
if the operator key signed it, so one node cannot revoke another.

## Watching for trouble

```march
let _ = ClusterNode.on_security_event(node, fn ev ->
  println(ClusterNode.security_text(ev)))
```

reports each refused handshake with its reason (an expired, revoked or foreign
certificate; a peer in the other mode), each frame dropped for a bad MAC, and
each certificate replacement: `CertReplaced(node_id, serial)` for this node's
own or a peer's, and `CertRefused(node_id, why)` when a new certificate did not
check out (a half-written file, a certificate for a key that is not there yet,
an expired or revoked one) and the old one was kept.
`ClusterNode.frames_rejected(node)` counts the dropped frames. A connection is
closed after three.

## Files

| file | written by | holds | where it goes |
|---|---|---|---|
| `operator.key` | `forge cluster keygen` | operator secret key | offline |
| `operator.pub` | `forge cluster keygen` | operator public key | every node |
| `<node>.key` | `forge cluster cert` | the node's secret key | that node only |
| `<node>.cert` | `forge cluster cert` | the node's certificate (base64) | that node |
