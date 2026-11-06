---
layout: docs
title: Hot Code Reload
nav_order: 10.9
permalink: /docs/hot-code-reload/
---

# Hot Code Reload

March can deploy new code to a running server **without restarting the process**.
Actors keep running and keep their state. Work that started on the old code finishes
on the old code: each actor handles the messages it already has queued with the
version they were sent to, then moves to the new version and migrates its state. New
work runs on the new code.

The mechanism is a signed patch of only the functions that changed, loaded into the
live process and activated as one step under a new **epoch** number. Every unit of
work (an actor, a task, a session) remembers the epoch it runs at and calls the
version of each function that was current at that epoch, so a partial rollout never
hands a live call the wrong shape of arguments. Two gates decide whether a patch may
widen what the node is allowed to do, and every signed request is sequenced so it
cannot be replayed.

In practice: no cold-start latency, no dropped connections, no TCP state reset, and no
need to drain traffic before a routine code push. Some edge cases are still open; read
[Current limitations](#current-limitations) before relying on it in production.

## On this page

**Start here**

- [When to use it](#when-to-use-it)
- [How it fits with the rest of March](#how-it-fits-with-the-rest-of-march)
- [How it works](#how-it-works)
- [Current limitations](#current-limitations)

**One server**

- [Server setup](#server-setup)
- [Configuring forge.toml](#configuring-forgetoml) and the [`[hot-reload]` reference](#single-server-forgetoml-reference)
- [Deploying](#deploying)

**Many hosts**

- [Multi-host deploys](#multi-host-deploys) and [the in-cluster control plane](#through-the-in-cluster-control-plane)
- [Pushing a topology: the `TOPOLOGY` verb](#pushing-a-topology-the-topology-verb)

**What happens to running work**

- [Actor state migration](#actor-state-migration): [queued messages](#messages-queued-during-a-deploy), [`migrate_msg`](#message-type-changes-and-migrate_msg), [drains](#drains), [when a deploy has to wait](#when-a-deploy-has-to-wait), [protocol changes](#protocol-changes)
- [Compatibility annotations](#compatibility-annotations)
- [Verifying migration soundness with `@invariant`](#verifying-migration-soundness-with-invariant) and [what `@invariant` accepts](#what-expressions-are-allowed-in-invariant)
- [What a build guarantees: `forge hot-reload check`](#what-a-build-guarantees-forge-hot-reload-check)
- [Contracts across versions](#contracts-across-versions): a deploy may loosen a refinement, never tighten it unproved
- [Deploying signature changes](#deploying-signature-changes)
- [Independent deploy pace (epoch-tagged dispatch)](#independent-deploy-pace-epoch-tagged-dispatch)

**Trust and durability**

- [Capability-safe deploys](#capability-safe-deploys): the two gates, `MARCH_DEPLOY_POLICY`, per-role closures, `--grant-cap`, the threat model
- [Sequenced releases: no replayed requests](#sequenced-releases-no-replayed-requests)
- [Artifact integrity: the signature covers the bytes](#artifact-integrity-the-signature-covers-the-bytes)
- [Restart durability](#restart-durability)

- [See also](#see-also)

## When to use it

Use a hot deploy for a **routine code push to a long-running node**: a handler
change, a bug fix, a new field on an actor's state with a `migrate_state` to fill it,
a protocol change that is compatible or that you roll out in the documented order.
What you keep is everything a restart would lose: in-memory actor state, open
connections, sessions in flight, and the warm process.

| The change | How it ships |
|---|---|
| A function body, an actor handler, a nested module's function | Hot patch of just that function |
| An actor's state shape | Hot patch plus a `migrate_state` (or a `@compat` annotation) |
| An actor's message type | Hot patch plus a `migrate_msg`, or old-format messages are dropped and counted |
| A function's signature | Hot patch; every caller must be in the same batch, unless the server supports epoch-tagged dispatch |
| A protocol a `choose` branch was added to | Hot patch, receivers of the choice before its chooser |
| `main`, a topology hook, generated protocol code, the standard library, the runtime | A restart; `forge deploy` plans it for you |
| A patch that reaches a capability the running version did not | Stops at the deploy-time gate until you `--grant-cap` it, and at the node's policy regardless |

Reach for a plain restart when the change is one of the last two rows, when the patch
stack has grown long (see [compaction](#restart-durability)), or when nothing on the
node is worth keeping.

## How it fits with the rest of March

| Concept | Where hot reload meets it | Chapter |
|---|---|---|
| **Actors** | The unit that migrates. An actor moves epochs at a marker in its own mailbox and runs `migrate_state` there; a supervisor restarts an actor killed at a hard drain on the new code. | [Actors]({{ site.baseurl }}/docs/actors/), [Supervision]({{ site.baseurl }}/docs/supervision/) |
| **Capabilities** | Each patched function carries its own IO capabilities. The deploy-time gate refuses a widening without `--grant-cap`; the node's `MARCH_DEPLOY_POLICY` refuses one regardless. | [Capabilities]({{ site.baseurl }}/docs/capabilities/) |
| **Choreography** | A session pins the epoch it formed in; a deploy changes only which protocol version new sessions form under, and drains sessions at loop boundaries. | [Choreography]({{ site.baseurl }}/docs/choreography/#changing-a-protocol) |
| **Refinement types** | `@invariant` on an actor is checked against `migrate_state` by the same SMT checker, with a counterexample on failure. | [Refinement Types]({{ site.baseurl }}/docs/refinement-types/) |
| **Topology and clustering** | `forge deploy` plans per pool, pushes a signed topology, and with a `[control]` section runs releases through the in-cluster control plane. | [Topology]({{ site.baseurl }}/docs/topology/), [Clustering]({{ site.baseurl }}/docs/clustering/) |
| **Observing a running node** | `EPOCHS` shows what each deploy is still waiting on; `WHICH` and `SOURCE` say which version of a function runs; the deploy key also signs debug requests. | [Observe]({{ site.baseurl }}/docs/observe/) |
| **Tooling** | `forge deploy hot`, `forge deploy --plan`, `forge hot-reload keygen` / `status` / `migrate-msg-stub`, `forge host init`. | [Tooling]({{ site.baseurl }}/docs/tooling/) |

---

## How it works

When you run `forge deploy hot`, the build tool:

1. Compiles your code to a shared library (`.so`), the same kind of file a server can
   load into an already-running process, without restarting it
2. Hashes every function's compiled body by its content, so two builds that produce
   the same code get the same hash; this is what lets the next step tell "changed"
   from "unchanged" without comparing source text
3. Diffs those hashes against a manifest of what the server currently has loaded, and
   uploads only the functions with a hash that actually changed
4. Signs each changed function with your **ed25519 key** (a public/private key pair;
   the server uses your public key to confirm the patch really came from you, the same
   idea as an SSH key) and sends it to the server
5. The server activates the whole deploy as one step, tagged with a new **epoch**
   number. Eligible new work runs the new code; running actors move over at their
   own pace, as the next section explains. Active caller frames, including the
   baseline `main`, retain their original routing epoch until they return

Actors that have a state schema change are migrated in mailbox order: messages already queued when the deploy lands finish on the old code against the old state, then the actor runs `migrate_state` and handles everything after that on the new code. New code never sees an old-shaped state. See [Messages queued during a deploy](#messages-queued-during-a-deploy).

Deploys are also **capability-gated**: each changed function brings its own IO capabilities, and both the deploy tool and the receiving node can refuse a patch that reaches for more authority than the running version (or the node's policy) allows. See [Capability-safe deploys](#capability-safe-deploys) below.

---

## Schema baselines and rollback

Every hot-reload base and patch embeds its actor schemas and manifest. Forge queries
`SCHEMAS` on the running server before migration checks, so the first state-changing
deploy does not require a local `.prev` file. The response describes the newest
activated schema for each actor and its release; actors still draining may be older.
A stale local baseline produces a warning and the server baseline wins. On legacy
servers that cannot answer the query, supply `--old-schemas` or restart onto a fresh
base. Malformed responses and connection failures abort the deploy.

Rollback is another signed deploy with a higher release sequence. If the faulty patch
changed state shape, the rollback needs an explicit reverse `migrate_state` that
preserves newer state. Re-uploading the original artifact without that migration is
refused. The rollback integration scenario verifies service continuity, restored
behavior and increasing release counters; automatic rollback is not provided.

## Server setup

The server binary listens on a Unix domain socket for reload requests. Pass the socket path at startup:

```sh
MARCH_HOT_RELOAD_SOCKET=/tmp/my_app.sock ./my_app_server
```

The socket is created automatically when the process starts. The `forge deploy hot` command connects to it over SSH.

---

## Configuring forge.toml

Add a `[hot-reload]` section to your project's `forge.toml`:

```toml
[package]
name    = "my_app"
version = "0.1.0"
type    = "app"

[hot-reload]
ssh_host   = "my-server"          # SSH host alias (from ~/.ssh/config)
socket     = "/tmp/my_app.sock"   # socket path on the remote host
public_key = "base64encodedkey="  # ed25519 public key (see below)
```

**Generating a key pair:**

```sh
forge hot-reload keygen
# Writes the secret key to ~/.march/ed25519_secret.key and prints the
# base64 public key to paste into forge.toml's [hot-reload] section.
```

Put the public key in `forge.toml` and embed the secret key in the server binary at build time (or pass it as an environment variable; see your server's startup flags).

---

## Single-server `forge.toml` reference

```toml
[hot-reload]
ssh_host   = "my-server"        # required: SSH host (alias or hostname)
socket     = "/tmp/app.sock"    # optional: Unix socket path on the remote (default: /tmp/march_hcr.sock)
public_key = "base64key="       # ed25519 public key (base64), embedded for signature verification
```

Only `ssh_host` is strictly required; `socket` falls back to `/tmp/march_hcr.sock` if omitted. The deploy uses `ssh` from the system PATH; your `~/.ssh/config` aliases and identity files are respected.

More `[hot-reload]` options serve
larger deployments: a `strategy` key (`"rolling"`, the default, vs. `"simultaneous"`), a
`health_check_url` polled between rolling-deploy steps, and `compact_after = N`
(see [Restart durability](#restart-durability)). For a fleet, see
[Multi-host deploys](#multi-host-deploys); the older repeatable `[[hot-reload.env]]`
table (each entry with its own `ssh_host`/`socket`/`public_key`, deployed with
`forge deploy hot --env <name>`) is still supported.

---

## Deploying

```sh
# Build and deploy in one step
forge deploy hot

# Deploy a pre-built artifact (e.g. cross-compiled for Linux)
forge deploy hot --so /path/to/my_app.so
```

> **Cross-host note.** Cross-target reload units are supported for
> `linux/amd64` and `linux/arm64`. Set `[hot-reload].target` and
> `module_prefix` in `forge.toml`; the running baseline advertises its target,
> ABI, prefix, and signing key (`HCR_INFO`). forge compares them with the
> patch's manifest before it uploads anything and names both on a mismatch;
> the server checks again after loading the patch.

On a successful deploy you see:

```
Connecting to my-server via SSH...
Deploying 3 changed function(s)...
Uploading artifact my_app.so...
  activated: Counter_dispatch
  activated: Api_handle_request
  activated: Metrics_record
Deploy complete: 3 function(s) activated.
```

If there are no changes since the last deploy, forge detects this from the content hashes and exits cleanly:

```
No changes detected — server is already up to date.
```

A change to the **standard library** is never a hot deploy. A stdlib change comes with
a toolchain or language change, and no stdlib function or actor has a dispatch slot
(see [Multi-host deploys](#multi-host-deploys)), so a patch could not deliver it. The
`.hcr_manifest` records a digest of the stdlib each build was compiled against
(`# stdlib_hash`); when it differs from the running build's, `forge deploy hot` refuses
before it connects, and `forge deploy --plan` plans the pool as a restart:

```
error: the standard library changed (stdlib 3f2a91c07d4e -> 8b0c5e11a2f9): stdlib code, its actors included, has no hot-reload slot, so a patch cannot deliver it; a stdlib change ships with a toolchain change and deploys by restart
error: deploy aborted, nothing was activated: deploy this build with a restart
```

A **toolchain upgrade that changes the hot-reload ABI** is a restart deploy too. Every
binary and patch records an ABI id (`# hcr_abi` in the manifest, `HCR_INFO` on the
server, `march-hcr-v5;triple=...;ptr=8` today). When the running server's id is older
than the patch's, `forge deploy hot` refuses before it uploads anything:

```
error: the running server was built by an older March toolchain (HCR ABI march-hcr-v4;triple=...) than this patch (march-hcr-v5;triple=...). The hot-reload ABI changed in between (march-hcr-v5 adds per-frame routing and closure lifetime hooks required by this patch), so this server cannot take hot patches from this toolchain, and nothing was deployed. Restart the server once on a base build from this toolchain (a cold deploy); hot deploys work again after that
```

The server repeats the check after it loads a patch (`ERR identity abi mismatch`), so an
older `forge` cannot slip one past it either. Restart once on a build from the new
toolchain; later hot deploys from that toolchain go through as before.

---

## Multi-host deploys

For more than one server, describe the app as a topology (see
[Topology]({{ site.baseurl }}/docs/topology/)) and let `forge deploy` decide, per pool,
how to get the hosts from what they run to what your working tree says: a hot patch, a
hot patch with a state migration or a protocol drain, a restart, a topology push, or
nothing. You never choose between "hot" and "restart".

```toml
# topology.prod.toml
[pool.back]
hosts = [{ host = "root@back-1", labels = ["db"] }, "root@back-2"]

[backend]
kind = "ssh"
```

```sh
forge host init --env prod      # once per host: user, dirs, systemd unit, keys, policy, firewall
forge deploy --plan --env prod  # what would happen, and why
forge deploy --env prod         # do it (asks first; --yes to skip)
forge topology status --env prod
```

`forge host init` prepares every host over ssh and records each one's target
(`linux/amd64`, `linux/arm64`): `forge deploy` builds for it, and refuses a patch built
for another target before it leaves your machine. The deploy then runs pool by pool: a
hot patch goes through an ssh tunnel to each node's reload socket, exactly as
`forge deploy hot` does (rolling with the health gate, `strategy = "simultaneous"`, or
`--canary N`); a restart uploads a base image built for the host and restarts the pool's
unit, and waits for the node's reload server before the next host; the signed topology
goes last. What was deployed is kept in `.forge/deploy/<env>/` and is what the next
plan compares against.

A hot patch can only replace **dispatch slots**. With the entry module as the prefix
(what forge passes), these are every function you write in the entry file: its
top-level functions, the functions of its nested modules (`Back.serve_one`), and your
actors' dispatch functions; plus anything under an explicit `[hot-reload]
module_prefix`. A closure travels with the function that builds it: an edit inside a
role body's `fn (n, st) -> ...` is a hot patch of the role body, and the closures it
builds from then on run the new code. A polymorphic function's specializations have
no slot of their own and travel with their callers the same way. A function's call
to itself stays a direct call, so a recursion already running finishes on the
version it started on, as a loop does. Never on the
boundary:

- `main` and every `<Mod>.main`: the running program's root frame cannot be swapped.
  A topology app's generated `main` is one; its hooks (`Back.start`) are slots, but a
  changed hook is a restart, because a hook runs once, at start.
- Code the compiler generates for you: the endpoint modules of a protocol
  (`Echo_Server`, `Echo_Run`, ...), which a session must finish on, and the control
  plane spliced into an app with a `[control]` section (its protocols, leader, Agent
  and control API), which is what runs a deploy and must not be swapped by one.
- The standard library, including its own actors (the cluster node that answers SWIM
  pings, session endpoints, the node-queue writers, ...): a deploy never activates,
  pauses or migrates them, and a stdlib change is a restart. Which actors and
  functions are the stdlib's, or the entry file's, is decided by where the compiler
  loaded them from, not by name, so an actor of yours named like a stdlib one, or
  declared in a file named like a stdlib file, keeps its slot.

A change the running base cannot swap (a function with no slot and no changed caller
that has one) is planned as a restart, and the plan says which functions. A one-line
edit flags only the function it is in: the names the compiler numbers (`$lam12`,
`$jp7`) are renumbered by any edit, but a function's hot-reload identity does not see
those numbers, so the functions that merely refer to one are not "changed".

The `[[hot-reload.env]]` fleet table below and `forge deploy hot --env <name>` keep
working for a project without a topology.

### Through the in-cluster control plane

A topology with a `[control]` section runs a control plane inside the cluster: the
nodes carrying the label it names are candidates, one of them leads, and every node
runs an agent that applies what the leader orders.

```toml
# topology.toml
[control]
candidates = "control"   # the host label of the nodes that may lead
port = 7947              # their control API (the default)
```

For such an environment `forge deploy` needs no ssh for a hot change. It builds and
classifies as above, then writes the hot pools and the topology push into one
**release**, a document signed with your deploy key where forge runs (the control plane
holds no keys), uploads the patches the release names to the candidates, sends the
release to any of them, and follows the leader until the release completes or halts:

```sh
forge deploy --env prod --plan    # the plan, which steps need ssh, and the release it would sign
forge deploy --env prod           # build, sign, upload, send, follow
forge deploy --env prod --status  # the leader's view: the release, its step, each node's report
forge deploy --env prod --audit 20  # the leader's audit log (the last 20 lines)
```

While it follows, forge prints each step (`step 1 of 2: ... hosts:canary(1) ...`) and the
leader's decisions as they change. A halted release stops the deploy with the leader's
reason (the step, the node, and why: a failed gate, or the node's own refusal); nothing is
rolled back, because a rollback is a new release, which only you can sign. A release that
outlives `--follow` (default 1800 s) keeps going on the leader; `--status` shows it.

`--canary N` makes each hot build's first step `N` nodes, gated on their staying healthy
for `--timeout` ms; the rest follow in the next step. Restart-class work (a runtime or hook
change, compaction, the first deploy of a build) can't be done by a node to its own
process: forge runs it over ssh as on the ssh path, in plan order, closing the release
before it and starting another after it. `--plan` lists those steps under "NEEDS SSH".

The control API is reached at each candidate host's address and the `[control]` port;
`FORGE_CONTROL_ENDPOINTS=host:port,...` overrides that (a tunnel, a test). `--via ssh`
deploys host by host over ssh instead, the break-glass path; a node then holds a release
the leader did not order, and the leader reports itself behind until you send a newer
one. `--via cluster` insists on the control plane. A build whose hosts span two targets
is refused on the cluster backend (a release names one patch per build): use `--via ssh`.
`FORGE_DEPLOY_NATIVE=1` builds a Linux host natively when it is this machine's own
target, instead of cross-building it; for hosts that share this machine's glibc.

**The leader's audit log.** Each candidate keeps `audit.jsonl` in its control directory
(`MARCH_CONTROL_DIR`, default `/tmp/march-control`), one JSON object per line, like a
node's audit log: `ts`, `type`, `leader` (the node that wrote it), and

| `type` | written when | fields |
|---|---|---|
| `release` | a release is offered to the leader | `seq`, `release` (its digest), `result`: `ok`, or why it was refused: `err_stale`, `err_fork`, `err_parent` (the compare-and-set on `parent`), `err_invalid`, `err_sig`, `err_parse`, `err_store`, `err_replicate`; `why` |
| `order` | the leader sends a step to a node | `seq`, `release`, `step`, `node`, `action`, `artifacts` |
| `step` | a node answers an order | `seq`, `step`, `node`, `result` (`ok`/`err`), `why` |
| `halt` / `complete` | the release ends | `seq`; a halt adds `step`, `node`, `why` |

The leader appends each line and copies it, about once a second, to every other
candidate it reaches, so the log outlives a change of leader. A candidate that was down
misses what was copied meanwhile; `forge deploy --audit` asks every candidate and shows
the union, in time order. The control API answers `AUDIT [n]` with one candidate's own
file. Past `MARCH_CONTROL_AUDIT_MAX_BYTES` (default 16 MiB) the file is renamed to
`audit.jsonl.1`, replacing the one before, so a candidate keeps at most twice that;
`AUDIT` reads both. Each node still writes its own audit log of what it applied (below).

**Who may write to the control API.** Reads (`STATUS`, `LEADER`, `AUDIT`, `CAS_CHECK`,
`CAS_GET`, a node's relayed version queries) are open: they are not confidential, and the
port belongs on the operator's network, like the cluster port. Writes are not:

- `RELEASE` takes only a release your deploy key signed (a standby forwards it to the
  leader as is, and the leader checks the signature).
- `CAS_PUT` takes an artifact only on a connection that first `STAGE`d a signed release
  naming it, no older than the candidate's newest; forge does this for you. An artifact is
  at most 64 MiB. Uploads that no stored release names yet are capped in total
  (`MARCH_CONTROL_CAS_PENDING_MAX_BYTES`, default 1 GiB; over it, `ERR cas_quota`), and one
  that no release adopts within `MARCH_CONTROL_CAS_GRACE_MS` (default 10 minutes) is
  removed, unless a persisted patch stack names it.
- The candidates' own copies (`RELEASE_COPY`, `AUDIT_COPY`) need the cluster's handshake,
  the same proof a cluster link takes: the cluster secret, or in certificate mode a
  certificate carrying `Ctl.Control:offer`. Anyone else is refused (`ERR
  unauthenticated`), and the candidate prints `control: refused an unauthenticated write`.

A candidate serves at most `MARCH_CONTROL_MAX_CONNS` connections at once (default 64; a
further one is answered `ERR busy`) and closes one that sends nothing for
`MARCH_CONTROL_IDLE_MS` (default 30 s). A release or audit body over 1 MiB is refused
before it is read. Candidates must run the same control-plane code: an older candidate
does not speak the handshake, so its copies to a newer one, and the newer one's to it,
are refused until both are upgraded.

`forge test --upgrade-from` deploys through the control plane too when the topology has a
`[control]` section, and `forge run --processes` gives each local process its own control
directory (`.forge/run/<node>.control`) and its control API on its cluster port + 1000.

---

## Pushing a topology: the `TOPOLOGY` verb

Pushing a topology changes what a node offers, so, like every reconciler action, it is signed. `Cmd_deploy_hot.push_topology` sends

```
TOPOLOGY <blake3 of the file> <signature> <size>
```

with the signature over `TOPOLOGY <blake3>` made with the deploy key. The server checks the signature **before** it accepts the body (`READY`), checks that the body hashes to the signed digest (`ERR digest_mismatch`), writes it to the service's state directory (`topology.toml`), records the digest and signature in the persisted state, and calls the runtime's topology hook, `march_hcr_on_topology(path)`, then answers `OK <blake3>`. At start, a persisted topology whose signature and digest still verify goes through the hook again, so the node comes back on the topology it had.

The signed copy is the one that takes effect. The server sets `MARCH_TOPOLOGY_VERIFIED_FILE` to that `topology.toml` when it starts, and `Topology.reload` reads it in preference to the unsigned `MARCH_TOPOLOGY_FILE`. After a push, the hook sends the process SIGHUP so the node re-reads it and opens its own offers, but only when a SIGHUP watcher is installed (`Topology.place` installs one): a program with no watcher would die of the signal. At start the hook does nothing; `Topology.place` applies the verified copy itself, so a restarted node comes back on the topology last pushed to it, not the one it was built with. With `MARCH_HCR_REQUIRE_RELEASE=1` the unsigned file is never read. The ssh reconciler backend (`forge topology apply --env`, `forge deploy --env`) still also writes the digest to `MARCH_TOPOLOGY_FILE` and signals the unit, for nodes built before this; a node whose server refused the signed push is not signalled.

---

## Actor state migration

When an actor's state record changes between deploys, the server needs to know how to upgrade the existing in-memory state of every live actor. You provide a `migrate_state` function:

```march
mod MyApp do
  needs IO.Console

  -- v2: add a `history` field to track previous counts
  actor Counter do
    state { count: Int, history: List(Int) }
    init  { count: 0, history: [] }

    on Inc() do
      let n = state.count + 1
      { count: n, history: List.append([state.count], state.history) }
    end

    on PrintCount(label) do
      println(label ++ int_to_string(state.count))
      state
    end
  end

  -- Magic name: <actor_lowercase>_migrate_state
  -- Called once per live Counter actor at deploy time.
  fn counter_migrate_state(old : { count: Int }) : { count: Int, history: List(Int) } do
    { count: old.count, history: [] }
  end

end
```

The naming convention is `<actor_name_lowercase>_migrate_state`. The parameter type is the **old** state shape; the return type is the **new** state shape. Every live actor of the type is migrated, however many there are.

### Derived migrations: adding a field needs no `migrate_state`

Most state changes only add fields. For those you write nothing: when a build knows the running version's schema, and an actor's state differs from it only by **added** fields, the compiler writes the `migrate_state` itself. Each kept field is copied; each new field takes its value from `init`.

```march
-- running:  state { count : Int }
actor Counter do
  state { count : Int, history : List(Int) }
  init { count: 0, history: [] }
  ...
end
-- no counter_migrate_state: the compiler derives
--   { count: old.count, history: [] }
```

The running version's schema is the `.march/<name>_hot.so.schemas.json.prev` that `forge deploy hot` keeps, so a forge project needs no setup. Outside forge, pass it with `--hcr-baseline <file>`. `forge deploy hot` says when it used a derived migration:

```
actor Counter: migrate_state derived from the running version's state (adds history from init)
```

A derived migration is checked like one you wrote: the same refinement and `@invariant` proofs, the same counterexample search, and the same live-data check before `ACTIVATE`. Copying a field keeps whatever the running version guaranteed of it, and a new field's `init` value is checked against its refinement. Both rules are proved once in the compiler's test suite, so with unchanged refinements there is nothing left for you to prove. If you also tightened a kept field's refinement, the build fails at that field with the running state that breaks it, and asks you to write the migration.

Nothing is derived when the change needs a decision. The deploy is then refused as before, and the refusal says why:

| Change | Why it is not derived |
|---|---|
| A field was removed | dropping data is your call (a rename looks like a removal plus an addition; for now, write the migration) |
| A field changed type | the old value has to be converted |
| A new field's `init` value reads an `init` parameter, or `init` is not a record literal | there is no constant to give a running actor |

A `migrate_state` you write always wins: the compiler derives one only when there is none. An actor declared in a nested module is not derived yet; write its migration by hand.

### Messages queued during a deploy

A deploy can land while an actor still has messages waiting in its mailbox. Those messages were sent to the old code, and the actor's state still has the old shape, so they are handled by the **old** code.

Every unit of work (an actor, a task, a session) runs at an **epoch**: the deploy it started under. Every call it makes resolves to the newest version of the function at or before its own epoch. A task inherits the epoch of the code that spawned it. The compiled `main` is the one exception: it always follows the newest code.

1. When a deploy activates, it gets a new epoch, and the server puts a **marker** in every live actor's mailbox, behind whatever the actor already has queued.
2. The actor works through the messages ahead of the marker at its old epoch: old handlers, old state.
3. When it reaches the marker, it moves to the new epoch. If its state schema changed, it runs `migrate_state` first. An actor several deploys behind runs each deploy's `migrate_state` in order. Every later message is handled by the new handlers, against the new state.

Each actor moves independently, at its own marker, so for a short while some actors of a type run the old code and others the new. The marker is never subject to a mailbox's overflow policy: an actor whose bounded mailbox is full at deploy time still gets it, behind its queued messages.

A sender that has already moved can send an actor a message in the new format before that actor reaches its marker. If the actor's message type changed in that deploy, the actor moves at that message instead of at the marker, so the new-format message runs on the new code and nothing is reordered.

### Message type changes and `migrate_msg`

Removing a handler, or changing a handler's parameter types, changes the actor's message type. `forge deploy hot` detects it from the handler signatures it keeps from the running version, and tells the server. A message in the old format that reaches the actor after it has moved (from a sender still on old code) is converted by `<actor>_migrate_msg` if you wrote one, and dropped and counted otherwise:

```march
mod CounterMsgV do
  type Msg = Inc(Int) | Reset | SetLabel(String)   -- the running version's handlers
end

fn counter_migrate_msg(m : CounterMsgV.Msg) : Option(Counter.Msg) do
  match m do
    CounterMsgV.Inc(n)      -> Some(Inc(n))
    CounterMsgV.Reset       -> Some(Reset())
    CounterMsgV.SetLabel(_) -> None     -- dropped on purpose, counted
  end
end
```

`Counter.Msg` names the actor's message type (the type its `on` handlers define). When the old type and the actor share a message name, qualify the new one by the actor: `CounterMsgV.Inc(n) -> Some(Counter.Inc(n))`. `forge hot-reload migrate-msg-stub Counter` writes this stub from the running version's handlers (add `--new <build>.so.schemas.json` to map kept handlers to themselves and removed or changed ones to `None`). The function is checked like `migrate_state`: it must be IO-free, take exactly one annotated parameter, return `Option(<Actor>.Msg)`, and match exhaustively. `forge deploy hot` refuses the deploy if its old type does not match the running version's handlers.

### Drains

Old epochs are retired by **drains**. After every deploy the older epochs drain automatically:

- **Soft deadline**: 5 seconds by default, or `MARCH_HCR_DRAIN_MS` milliseconds (`0` turns it off). An actor that has not reached its marker by then moves at once, as if the marker were at the front of its mailbox. The messages still queued ahead of it then run on the new code, except old-format messages (see above), which take `migrate_msg` or are dropped and counted. A handler that is already running is never interrupted.
- **Hard deadline**: off by default; `MARCH_HCR_HARD_DRAIN_MS` milliseconds arms it. Every actor still pinned to a drained epoch is killed, and its supervisor restarts it on the new code with its `init` state (an unsupervised actor just dies, and its state is lost). Other units still on a drained epoch are told to stop.

A drain can also be started by hand with the reload server's `DRAIN <signature> epoch:<E> soft_ms:<n> hard_ms:<n>` request, which drains every epoch up to `E`. It is signed like `ACTIVATE` (over `DRAIN epoch:<E> soft_ms:<n> hard_ms:<n>`), and `E` must be below the current epoch: every live unit is pinned at or below the current one, so draining it with a hard deadline would kill every actor in the process. Every drain request is audited (`type` `drain`). Like every signed request, it must be wrapped in a release once the node holds one (see "Sequenced releases").

An actor that hosts work from an older epoch, such as a session party, takes an **epoch hold**: while it holds one, it stays on its epoch at its marker and at the soft deadline, and moves when the last hold is released. Messages in a newer format that reach it meanwhile are set aside and replayed, in order, once it moves. The hard deadline still applies.

### When a deploy has to wait

Each function keeps up to **three** live versions. A version stays loaded while any unit could still call it: while some unit's epoch lies between that version's epoch and the next newer version's. When a deploy needs a fourth version of a function that every older version is still serving, the server does not fail it. It answers

```
WAIT epoch:5 pins:3 deadline_ms:40000
```

and keeps the deploy queued. `forge deploy hot` prints it (`waiting on 3 unit(s) pinned to epoch 5, hard deadline in 40s`) and retries every second, for up to `MARCH_DEPLOY_WAIT_S` seconds (600 by default). A hard drain deadline guarantees the wait ends. `forge hot-reload status` shows the pinned epochs and the counters (messages deferred, converted and dropped, actors killed).

### Protocol changes

A session pins the epoch it formed in, so a deploy never changes the protocol under a
session that is already running. What a deploy can change is which protocol *new*
sessions form under, and that depends on the kind of change (see
[Changing a protocol]({{ site.baseurl }}/docs/choreography/#changing-a-protocol)):

- **Same fingerprint** (handler bodies, a role's `needs` line): deploy in any order.
- **A `choose` gaining a branch**: compatible, provided every role that *receives* the
  choice is upgraded before the role that *makes* it. Each protocol's `<P>_Msg.compat()`
  table, computed at build time against `.forge/protocols/<P>.json` (the previous
  version, which `forge build` keeps), says which roles may run the new version beside
  old peers, and access points form mixed-version sessions by it. Offers carry their
  fingerprint in their names, so a node can offer both versions of a role at once.
- **Anything else**: breaking. Old and new binaries refuse each other when a session
  forms; offer both versions while the deploy rolls through.

When one binary both makes and receives the changed choice (a replicated monolith), the
change takes two deploys: first a build with `--protocol-expand <P>:<label>` (receivers
take the new version, the chooser stays on the previous one and cannot pick the new
branch), then the plain build. `forge deploy` does this for you: `--plan` shows the
split, the first `forge deploy` builds the expand, and the next one the contract. It
compares against what the environment runs (`.forge/deploy/<env>/protocols/`), not
against the previous build.

Unlabelled protocol steps get positional wire tags that an inserted step renumbers, so
the compiler warns at each one in a protocol your topology uses; label them before you
need to change the protocol.

Typed remote messages (`Node.send`, `@[remote]`) carry their type's schema hash beside the
tag, so an actor built from a newer or older version of a message type converts it with
its `migrate_msg` or refuses it with `DELIVERY_FAILED` instead of misdecoding it
([Clustering]({{ site.baseurl }}/docs/clustering/)).

A cluster node's own long-lived tasks follow a deploy too. Each link has a reader task
that routes every remote delivery to its local actor, and a task keeps the epoch it
started at. So a reader started before the deploy would route later deliveries through
the old code and stamp them with the old epoch, and an actor whose message type changed
would convert or drop a message the peer had already sent in the new format. Instead, a
reader that finds its epoch draining hands its connection, at the next frame it reads, to
a new reader started on the new code, and that reader delivers the frame. The node's
ticker and acceptor move the same way, so a cluster node does not keep the old epoch
pinned. A connection with no traffic moves at its next frame; the acceptor at its next
inbound connection.

Two limits for now. After a deploy, `Topology.reoffer` reopens a role through the `open`
function the old code built, which still runs the old code; re-offer from an actor whose
handler the deploy replaces instead. And a hot patch carries its own copy of the runtime,
so a session started by patched code can crash the process
(`specs/todos/2026-09-25-hcr-patch-so-private-runtime-copy.md`).

---

## Compatibility annotations

Without a `migrate_state` function, `forge deploy hot` enforces strict compatibility: if the state schema changed, the deploy is rejected. You can relax this with `@compat`:

```march
-- Default: any schema change requires migrate_state
@compat(full)
actor Counter do ... end

-- Allow adding fields with no migration at all (prefer a derived or written migrate_state)
@compat(forward)
actor Counter do ... end

-- Skip schema checking entirely (dangerous — use only for rapid iteration)
@compat(any)
actor Counter do ... end
```

| Policy | What's allowed without `migrate_state` |
|---|---|
| `full` (default) | No changes; any change requires migration |
| `forward` | Adding new fields |
| `any` | Any change; no migration check |

A [derived migration](#derived-migrations-adding-a-field-needs-no-migrate_state) counts as a `migrate_state` under every policy: adding fields with constant `init` values deploys under `full` too, because the migration exists and was checked. `forward` and `any` matter only where nothing could be derived, and there they let the deploy through with **no** migration, so a running actor keeps its old-shaped state. Prefer a migration.

For production deployments, `full` is safest: every state transition then has a migration, written or derived, that the compiler checked.

---

## Verifying migration soundness with `@invariant`

If your actor has a state invariant (a condition that must hold for every live actor), you can annotate it and the compiler will **prove** that your `migrate_state` function preserves it before the deploy is allowed through.

```march
-- The actor invariant: count is always non-negative
@invariant(count >= 0)
@compat(full)
actor Counter do
  state { count: Int }
  init  { count: 0 }

  on Inc() do { count: state.count + 1 } end
end
```

When you add a field and write a migration:

```march
@invariant(count >= 0 && len(history) == count)
@compat(full)
actor Counter do
  state { count: Int, history: List(Int) }
  init  { count: 0, history: [] }
  ...
end

fn counter_migrate_state(old : { count: Int }) : { count: Int, history: List(Int) } do
  { count: old.count, history: [] }
end
```

`forge deploy hot` runs the compiler's migration checker before uploading anything. If the migration cannot be proven sound, the deploy is aborted:

```
-- ERROR --------------------------------- src/my_app.march

`counter_migrate_state` does not satisfy its return type constraint on all code paths.

The return type requires:

    count >= 0 && len(history) == count

A counterexample was found:

    old = { count: 1 }

30 |   fn counter_migrate_state(old : { count: Int }) : { count: Int, history: List(Int) } do
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

    Every branch must produce a return value satisfying `count >= 0 && len(history) == count`.

error: migration check failed — deploy aborted
```

The error names the function, shows the constraint, and gives a concrete counterexample: with `old = { count: 1 }`, returning `{ count: 1, history: [] }` violates `len(history) == count` because `len([]) = 0 ≠ 1`.

Fix the migration to satisfy the invariant for all inputs:

```march
fn counter_migrate_state(old : { count: Int }) : { count: Int, history: List(Int) } do
  -- Reset count to 0 so history: [] is consistent with count == 0
  { count: 0, history: [] }
end
```

Or keep the count and build the history to match:

```march
fn counter_migrate_state(old : { count: Int }) : { count: Int, history: List(Int) } do
  -- Fill history with `count` placeholder entries
  let hist = List.replicate(old.count, 0)
  { count: old.count, history: hist }
end
```

Both satisfy `len(history) == count`. The compiler verifies this using an SMT solver; no input can slip through.

---

## What expressions are allowed in `@invariant`

Invariant predicates support:

| Expression | Example |
|---|---|
| Arithmetic comparisons | `count >= 0`, `size < capacity` |
| Boolean connectives | `count >= 0 && len(history) == count` |
| `len` on list fields | `len(history) == count` |
| Field access | `count`, `capacity`, `history` (bare names refer to `state.*`) |
| Negation | `!is_empty` |
| Integer literals | `count >= 0`, `size > 1` |

Invariants can only reference the actor's own state fields. External function calls and heap allocation are not allowed in predicates.

An `@invariant` outside this grammar can't be checked across a deploy, so a `--hot-reload`
build stops with an error at the part it can't read
(`invariant_not_deploy_checkable`). Building with `--accept-unproved <Actor>.state` (or
`<Actor>`) turns it into a warning and signs that override into the patch, where the reload
server's audit log records it (see below). A state-field or handler-parameter refinement
the schema can't record (a call with more than one argument, for example) is not an error,
but a deploy of that actor is **refused** unless the same override names it.

## What a build guarantees: `forge hot-reload check`

`forge hot-reload check` (or `march --check --guarantees FILE`) prints one block per actor
and protocol, saying what this build established and what it rests on. It runs the same
check as `forge check`, against the last deploy's schema when there is one
(`.march/<name>_hot.so.schemas.json.prev`), and changes no verdict: an error is still an
error, with the same exit code.

```
actor Counter: not checked
  state refinements        proved: 3 sites in init and handlers
  @invariant               not checked: init and handler results are not checked against it; a hot deploy checks it on the migrated state
  handler contracts        proved: 1 site where a message is built
  migrate_state (derived)  proved: 1 site against the deployed build
protocol Relay (2 roles): not checked
  projection        checked (compiler): the two roles' projections are dual
  deadlock freedom  not checked: no proof covers this protocol yet
runtime: assumed
  mailbox order, Actor.call replies, DOWN delivery  assumed: the runtime is trusted; nothing here proves it
```

| Label | Meaning |
|---|---|
| `proved` | The refinement checker proved every obligation of that kind in the code that runs. |
| `violated` | It found a counterexample; the build reports it as an error too. |
| `not proved` | Some obligation was neither proved nor refuted; the line gives the checker's reason. |
| `not checked` | The program states a guarantee nothing checks yet. This line is the only place it is said. |
| `checked (compiler)` | A compile-time check that is not a proof about a model (protocol projection). |
| `assumed` | The trust boundary: the runtime, and messages from other nodes to an `@[remote]` actor. |

A block's header is its weakest line, `assumed` aside. Two gaps are reported as
`not checked` today: `@invariant` is used only across a hot deploy (as the migration's goal
and, from the deployed build, as a hypothesis), and nothing yet proves a protocol free of
deadlock.

## Contracts across versions

The new code's handlers *assume* the refinements it declares: a state field's
(`count : {Int | _ >= 1}`), a handler parameter's (`on Bump(n : {Int | _ > 5})`) and the
`@invariant`. A live actor's state, and the messages already queued for it or still being
sent from code on an older epoch, were only ever checked against the *running* version's
contracts. So `forge deploy hot` proves, for every actor, that **the running version's
contracts imply the new ones**:

| What | Law | When it is checked |
|---|---|---|
| The state | old field refinements and `@invariant` imply the new ones | with a `migrate_state`: of its result, from the old state; without one and with the same fields: of the state as it is |
| A handler's parameters | each old parameter refinement implies the new one | when the message type is unchanged (otherwise `migrate_msg` converts every old message) |

Loosening a contract always passes. Tightening one is refused unless it follows from the
old contract, or a `migrate_state` re-establishes it:

```
migration: Tally.state: REFUSED, not proved that (count >= 0) implies (count >= 1) (the running version's contract must imply the new one; pass --accept-unproved Tally.state to deploy anyway)
migration: Tally.Bump: REFUSED, not proved that parameter 0: (p0 > 0) implies (p0 > 5) (the running version's contract must imply the new one; pass --accept-unproved Tally.Bump to deploy anyway)
error: migration VC failed — deploy aborted
```

Before this check, a deploy like this one went through unchecked. The refinements weren't
part of the schema at all, so it looked like no change. The new handlers' proofs then
rested on a fact the live actors didn't meet: a division "proved" safe by `count >= 1`
could still divide by zero.

**What refuses a deploy.** A migration that a counterexample shows breaks the new contract
always does. A law that is not proved, or not checked (a predicate the schema could not
record, a running version built by a compiler older than this check, a contract on a handler
whose messages `migrate_msg` converts), refuses the deploy too, unless you name it:

```bash
forge deploy hot --accept-unproved Tally.state
```

`--accept-unproved` takes `<Actor>.state`, `<Actor>.<Handler>`, or `<Actor>` for all of an
actor's laws, repeated or comma-separated. A counterexample can't be accepted. When an actor
has any contract, the check needs the compiler: if `MARCH_BIN` isn't set and no
`_build/default/bin/main.exe` is found, the deploy is refused rather than skipped.

**The override is part of the patch, and the server logs it.** forge passes
`--accept-unproved` to the build, and the compiler writes the accepted laws into the
actor's schema in the signed image (`"accepted_unproved": ["state"]`, or `["*"]` for the
whole actor). The server's audit line for the activation copies them:

```json
{"ts":…,"type":"activate","fn":"Tally_dispatch",…,"accepted_unproved":["state"],"result":"ok"}
```

So the audit log answers "what was deployed without its contract proved, and who signed
it." A patch built elsewhere (`forge deploy hot --so …`) must be built with the same
`march --accept-unproved …`: forge refuses an override the patch doesn't carry.

### Migrations are checked on every build

You don't have to wait for `forge deploy hot` to find out that a migration is wrong.
Every `march --check` and every build (so the editor too) checks each `<actor>_migrate_state`
and `<actor>_migrate_msg` against the new actor's contracts. The checker can't always prove
an obligation inside a migration. When it can't, it doesn't give up with a hint. The
migration's parameter is every old value the runtime could hand it, so the compiler runs the
migration on small old values and looks at what the new code would receive:

```march
fn tally_migrate_state(old : { count : Int }) do
  { count: old.count, hist: Nil }          -- the new state needs count >= 0
end

fn tally_migrate_msg(m : V1.Msg) : Option(Tally.Msg) do
  match m do
    V1.Bump(n) -> Some(Tally.Bump(n))      -- the new handler needs n > 0
    V1.Reset -> None
  end
end
```

```
`tally_migrate_state` can produce a state the new actor rejects. [refinement_violated]

`Tally` requires  _ >= 0 (field `count`)
but tally_migrate_state({ count: -1 }) returns { count: -1, hist: [] }

`tally_migrate_msg` can produce a message the new handler rejects. [refinement_violated]

`Tally.Bump` requires  _ > 0
but tally_migrate_msg(V1.Bump(0)) returns Some(Tally.Bump(0))
```

Fix the migration, or say what the old values guarantee. `old : { count : {Int | _ >= 0} }`
proves the state, and `V1.Bump(n) -> if n > 0 do Some(Tally.Bump(n)) else None end` proves
the message. When no small input breaks the contract, the obligation stays an ordinary
"not verified" hint. It is never an error the program can't trigger.

**The deployed build's contracts count.** If the project was hot-deployed before, forge has
kept the running version's schemas in `.march/<name>_hot.so.schemas.json.prev`, and the
compiler reads them (pass `--hcr-baseline <path>` to name another file). A state field
refinement of the running version, and each `@invariant` conjunct that mentions one field,
is assumed of the matching field of `migrate_state`'s record parameter. So the migration
above proves against a running version whose `count` was `{Int | _ >= 0}`, even though
`old : { count : Int }` doesn't say so. Likewise, an old message that the running handler's
refinement would have refused is not offered as a counterexample. Two things don't use the
baseline yet: a `migrate_state` parameter of a named record type, and the match binders of a
`migrate_msg` in the proof (the running handler's refinement only filters the inputs tried).

### Undecided migrations are checked on the live data

When the checker can neither prove a migration nor find an input that breaks it (a predicate
that calls a function the prover doesn't reflect, say), `forge deploy hot` refuses it unless
`--accept-unproved` names it. An accepted migration is still checked, on the data it will
actually meet. A `--hot-reload` build carries, beside each `<actor>_migrate_state` whose actor
has a state contract, a function that runs the migration and evaluates the new field
refinements and `@invariant` on the result. Before `ACTIVATE`, the reload server runs it on a
copy of every live actor's state, on the actor's own thread between two of its handlers. Any
failure refuses the deploy, naming the actor, and nothing changes: the actors keep running the
old code.

```march
fn not_137(n : Int) : Bool do n != 137 end

@invariant(not_137(count))
actor Counter do
  state { count : Int, label : String }
  ...
end

fn counter_migrate_state(old : { count : Int }) : { count : Int, label : String } do
  { count: old.count, label: "v2" }
end
```

```
  COMMIT_BATCH failed: ERR migration_check Counter pid:0 @invariant: not_137(count)
  refused: Counter's new migrate_state fails on its live state (pid:0 @invariant: not_137(count)); nothing was activated
```

When every live state passes, the server's log says so:

```
[hcr] migrate check: Counter: checked on live data (3 actors)
```

That is weaker than a proof: it covers the states that exist when the deploy runs, not
every state the migration could meet. A conjunct outside the deploy gate's grammar (see
"What expressions are allowed in `@invariant`"), or one that calls a function not declared
beside the actor, isn't evaluated. The log line names it (`not evaluable at run time:
…`), and it is never dropped silently. An actor that doesn't answer within 5 seconds
(`MARCH_HCR_MIGRATE_CHECK_MS` on the server) refuses the deploy too, as does a migration that
panics on a live state. An actor still catching up to an earlier deploy is asked again until
it has.

Messages get the same treatment as they arrive. In a `--hot-reload` build, a message that
`migrate_msg` converts but that fails the new handler's parameter refinements is dropped
and counted, as a `None` is, instead of reaching a handler whose contract it breaks.

Two limits. The check calls the new `migrate_state` and the predicates' functions in the new
image, but a function *they* call that this deploy also changes still runs its running
version during the check. And a state can still change between the check and the actor's
switch to the new code: the check runs before `ACTIVATE`, and the actor keeps handling
messages until it reaches its epoch marker.

---

## Deploying signature changes

A running caller must keep calling versions compatible with its compiled arguments.
Current servers advertise `FRAME_PINS 1`: every active frame retains its routing epoch,
including nested calls and baseline `main`; closures retain their creation epoch until
released. New actor work uses the actor's current epoch after mailbox migration.

Generated topology role offers enter the accepting actor or task's epoch before
creating a new session endpoint. Their entry adapters check the captured environment's
layout and parameter ownership before crossing versions. An incompatible environment
is refused with a restart diagnostic. The check conservatively includes reachable
nominal types, including types carried by handles, so some layout changes require a
restart even when a more precise compatibility proof might permit them. An already-running
session retains its epoch; ordinary saved closures and `offer_<Role>` callbacks retain their creation epoch.

Forge permits signature changes only with this frame-pinning support. It records caller
coverage and warns when callers remain on old versions. An older server requires a
restart onto the current toolchain or an expand-contract rollout. A loop that never
returns can retain old versions indefinitely and eventually exhaust version capacity;
restart or refactor the loop to return to an actor mailbox between requests.

### Parameter borrow modes are part of the signature

A boundary function's `sig_hash` covers more than its types. The compiler decides, from
the body, whether each heap parameter (a `String`, a `List`, any ADT) is **borrowed** (the
callee only reads it, and the caller keeps its reference) or **owned** (the callee takes
the reference, for example because it stores the value, returns it or passes it on to an
owning position). A caller is compiled against those modes. So a body edit that turns a
borrowed parameter owned changes the function's ABI even though its source signature did
not change: running code would keep using a value the new code frees (a use-after-free),
and the reverse change would leak one reference per call. Records and tuples are always
passed owned, so a change to how a body uses one never changes the ABI.

Each boundary function's `sig_hash` (in the `.hcr_manifest`, in the binary's dispatch
table and in `ABI_QUERY`) is therefore a hash of the type signature **and** one mode per
parameter; the manifest also lists the parts (`tsig=` and `modes=`, `b` borrowed, `o`
owned). A deploy that changes only a mode is always refused, naming the parameter:

```
error: a hot deploy cannot change a boundary function's parameter borrow mode: parameter 1 of Handler.count changed from borrowed to owned. Code already running was compiled against the old mode and would use a reference the new code releases (a use-after-free) or never release one it now owns (a leak per call). Deploy this build with a restart, or keep the mode (a parameter becomes owned when the body stores it, returns it or passes it to an owning position)
error: deploy aborted, nothing was activated
```

Borrow-mode changes remain conservatively refused even with frame pinning. Deploy
such a change with a restart; body-only changes that retain the modes can deploy hot.

A server records the `sig_hash` of each version it activates (from the patch itself), so
the check applies to every deploy, not only the first one after a restart.

---

## Independent deploy pace (epoch-tagged dispatch)

Epoch routing lets callers and callees advance independently while retaining the
versions needed by active frames and closures.

**Epoch-tagged dispatch** is the alternative mechanism that makes that safe, and the
idea is closer to keeping a small version history than to any kind of locking. Every
deploy batch is tagged with a **monotonically increasing epoch number**; think of it
like a global "build number" that only goes up. Each function keeps not just its
newest version but a short rolling history of recent versions too (its **ring slots**,
a small, fixed-size buffer of "this version, introduced at this epoch"). And critically,
every *unit of work* (an actor, a task, a session) remembers the epoch it runs at.

When a caller invokes a function under epoch-tagged dispatch, the runtime doesn't just
jump to the newest version: it walks the callee's ring slots and picks **the newest
version that existed at or before the caller's own epoch**. So:

- An actor still at epoch 5 (it has not reached its marker yet) calls `B.foo` → it gets
  the `B.foo` that was current *at epoch 5*, the version its code was built against.
- The same actor after its marker, now at epoch 7, calls `B.foo` → it gets the newest
  `B.foo`, because its own epoch has caught up.

A unit of work only sees versions compatible with its own epoch, never
anything newer, whether the call is made from the base binary or from a hot patch. It
picks up the new versions when it moves epochs (an actor at its marker; a task or session
never, so it finishes on the code it started with). No coordination, no batching, no
window where a live call could receive the wrong shape of arguments.

This changes what the coordinated upgrade gate does: once a server supports epoch-tagged
dispatch, a missing caller is no longer a hard error: the gate downgrades to an
advisory warning, because epoch routing has already made it *safe* for that caller to
lag behind; the deploy proceeds. Mechanically, forge asks the server for the batch's
epoch number (via a `GET_EPOCH` request) before deploying, and the server hands back a
number that only increases. If the server doesn't support this exchange at all, forge
falls back to epoch 0 and the plain coordinated upgrade gate applies exactly as described
above, so this feature degrades gracefully rather than silently skipping the safety
check.

### Compatibility table

| Server supports epochs | Forge supports epochs | Result |
|---|---|---|
| No | No | Coordinated upgrade gate only (hard error on a missing caller) |
| Yes | No | Same; forge never asks for an epoch, so it never uses the feature |
| No | Yes | Forge asks for an epoch, the server doesn't answer, forge falls back to epoch 0, same as above |
| Yes | Yes | Full epoch-tagged routing; the gate becomes an advisory warning instead of a hard error |

---

## Capability-safe deploys

A hot deploy pushes new code straight into a running process: it's compiled, shipped to the server, loaded into the live process's memory with `dlopen` (the OS mechanism for loading a shared library at runtime, the same one plugins use), and starts handling requests. The ed25519 signature on each patch answers one question: *is this really from us?* It leaves a second, equally important one unanswered: *is this code allowed to do what it does?*

A patch you signed could call `file_delete`, open a network connection, or spawn a process, even if the version it replaces never touched the filesystem or the network at all. Signing proves **origin**, not **behavior**.

Capability-safe deploys add the missing check. March already knows each function's IO capabilities from compile time: its `needs` declarations plus the effects inferred from its body. A hot deploy brings those capabilities with it, and **two gates** decide whether the new code may run: one on your machine when you deploy, and one on the server when it activates.

### The unit of enforcement: per-activated-function caps

A hot deploy only re-activates the functions that **changed**. Each changed function brings **its own** inferred IO capabilities (the effects its own body requires), not the capabilities of the whole artifact.

This granularity matters. `--hot-reload` links the entire standard library into every patch, so a *whole-artifact* capability set would be dominated by the stdlib's footprint (filesystem, network, process, clock, …) and would be identical for every app, useless for a policy. Gating on the **changed function's own caps** is what makes the check discriminating: a patch that adds `file_write` to one function is caught exactly because that function now declares `IO.FileWrite`, regardless of what the rest of the linked code can do.

The trust boundary follows from this: the **base server binary is trusted**: you built and started it, with a policy. Each **hot-patched function** is the mobile code the gates govern.

### Two gates

1. **Monotonicity gate (deploy-time, on your machine).** *Monotonicity* means the capabilities can only move in one direction. Across deploys, a function's set of capabilities may get *smaller* on its own, but it can't get *bigger* without your say-so.

   - **Dropping** a capability is always allowed: a function that used to write files and no longer does is strictly safer, so it deploys without ceremony.
   - **Adding** a capability is called a **widening**: for example, a function that gains the ability to write files, open a socket, or spawn a process that its running version didn't have. A widening **stops the deploy** and asks you to confirm it explicitly with `--grant-cap`.

   The point of this one-directional rule is that a routine code push can't grant your running system new powers unannounced; the moment a patch reaches for more, you have to sign off on it by name.

2. **Node policy gate (activation-time, on the server).** If the node sets `MARCH_DEPLOY_POLICY`, the server will not activate any function with capabilities that exceed the node's policy, regardless of who signed it. This is enforced independently of the deploy tooling, so it stays in force even if the deploy pipeline is bypassed or compromised.

### A worked example

Start from a server with a reloadable handler that only writes to the console:

```march
-- server.march (v1)
mod App do
  needs IO.NetListen
  needs IO.Console
  mod Server do
    needs IO.Console
    fn handle(x : Int) : Int do
      println("handle v1 (console only)")
      x + 1
    end
  end
  fn main() do
    println("cap-demo server up")
    let _ = Server.handle(1)
    match tcp_listen(9099) do
      Err(e) -> println("listen err: " ++ e)
      Ok(fd) -> let _ = tcp_accept(fd)  println("server shutting down")
    end
  end
end
```

`Server.handle`'s own capabilities are just `{IO.Console}`. Run the node with a policy that permits only console I/O:

```sh
# on the server host
printf 'IO.Console\n' > /etc/march/deploy-policy.txt
MARCH_HOT_RELOAD_SOCKET=/tmp/app.sock \
MARCH_DEPLOY_POLICY=/etc/march/deploy-policy.txt \
  ./cap_server
```

Now a `v2` that adds a filesystem write to the same function:

```march
  mod Server do
    needs IO.Console
    needs IO.FileWrite
    fn handle(x : Int) : Int do
      println("handle v2 (now writes a file!)")
      let _ = file_write("/var/log/app-debug.log", "handled " ++ int_to_string(x))  -- needs IO.FileWrite
      x + 2
    end
  end
```

`Server.handle`'s own caps are now `{IO.Console, IO.FileWrite}`.

**Step 1: deploy v2 with no grant.** The monotonicity gate aborts on the client, before anything is uploaded:

```
$ forge deploy hot --so v2.so
Deploying 1 changed function(s)...
error: hot deploy would add authority not held by the running version
  running version caps:  IO.Console
  new version adds:      IO.FileWrite (from Server.handle)
  A hot deploy may only narrow authority. To authorize this widening, re-run with:
      forge deploy hot --grant-cap IO.FileWrite
error: capability widening — deploy aborted
```

The diagnostic names the exact capability *and* the specific function that introduced it. Widening the authority of a live system mid-flight is exactly the event an operator should consciously sign off on.

**Step 2: grant the widening, but the node policy forbids it.** With `--grant-cap` you pass the deploy-time gate, the artifact uploads, and the server's policy gate rejects the activation:

```
$ forge deploy hot --grant-cap IO.FileWrite --so v2.so
Deploying 1 changed function(s)...
  granted widening: IO.FileWrite (via --grant-cap IO.FileWrite)
Uploading artifact v2.so...
Artifact uploaded.
  FAILED Server.handle: ERR cap_policy IO.FileWrite — deploy rejected by node capability policy
  Rolled back: 1 function(s) failed, server state unchanged.
error: 1 function(s) failed to activate
```

The node had the final say. The batch rolled back cleanly; the live system is unchanged.

**Step 3: a node with a policy that permits it.** Update the policy on the node and restart it (the policy is read once at startup):

```sh
printf 'IO.Console\nIO.FileWrite\n' > /etc/march/deploy-policy.txt
# restart the server so it re-reads the policy
```

```
$ forge deploy hot --grant-cap IO.FileWrite --so v2.so
Deploying 1 changed function(s)...
  granted widening: IO.FileWrite (via --grant-cap IO.FileWrite)
  activated: Server.handle
Deploy complete: 1 function(s) activated.
```

The same signed patch is admitted here and rejected on the console-only node: per-node authority, enforced at the node.

### Configuring `MARCH_DEPLOY_POLICY`

`MARCH_DEPLOY_POLICY` is the path to a newline-delimited file of permitted capability paths. The check is **subsumption-aware**: listing a parent capability permits its children (`IO.Network` permits `IO.NetConnect`, `IO.NetConnect.TLS`, `IO.NetListen`, …). See [Capabilities]({{ site.baseurl }}/docs/capabilities/) for the full hierarchy.

```
# /etc/march/deploy-policy.txt — this node may only gain console + read-only + outbound TLS
IO.Console
IO.FileRead
IO.NetConnect.TLS
```

A node with this policy will never *admit a hot patch* that declares file-write, process-spawn, or foreign-FFI authority, regardless of signature.

**The policy speaks about IO capabilities only.** The gate checks every capability under the `IO` lattice (`IO`, `IO.Console`, …, including an unknown `IO.` path) and does not police one outside it: a proof capability such as `Session.Live`, `ClusterNode.Live`, `Actor.Introspect` or your own `Db.Migrated`, or an FFI root. Those carry no IO authority of their own. The type system already decides who can hold one (only the declaring module mints it, from a `Cap(IO)` that is charged to the minter), and whatever IO a proof capability's dictionary performs is charged to the code that minted it: a session's transport belongs to the runner, not to the role body it is handed to. Calling foreign code is charged `IO.Foreign`, which the policy does police. This is the rule the compiler's own grant checks follow (a role's `needs` and `main`'s grant skip non-IO caps), and a pool's `caps` in a topology are IO caps, so the policy `forge host init` generates from them never names a proof capability. In practice it means a role body, whose own caps always include the session it is handed (`caps=IO.Console,Session.Live`), hot patches under that policy; a patch that also reaches an IO capability the policy lacks is still refused, proof capabilities beside it or not.

> **An empty policy *file* is the opposite of permissive.** Only an **unset** (or
> pointing-at-nothing) `MARCH_DEPLOY_POLICY` means "no policy is loaded" ⇒ permissive,
> which is the default for backward compatibility. The moment the server can open a
> policy file at all (even a completely empty, zero-byte one), it treats that as "a
> policy is active, and it permits zero capabilities," so it will then reject *every*
> function that declares any IO capability at all. If you want permissive, unset the
> variable entirely; don't point it at an empty file.

A line `serves <Proto.Role> ...` names the roles this node serves, and scopes the [per-role closure](#per-role-closures-activate6) check to them. The policy `forge host init` writes for a pool is the pool's `caps` (or its derived ones), the caps the topology runner charges to its roles, and that line:

```
# /etc/march/<project>/back.policy, generated
IO.Clock
IO.Console
IO.Mut
IO.Process
IO.Spawn
serves Echo.Server
```

A role the node does not serve is another pool's (a shared build carries every pool's roles) or the control plane's (`Ctl.Agent` and `Ctl.Control`, generated into every node's `main` when the topology has a `[control]` section, and charged to it like the runner). This pool's policy is not the bound on those, and granting their closures here instead would widen what any patch on the node may do. A bare `serves` says the node serves no role. A policy with no `serves` line bounds every role's closure, so a hand-written policy behaves as it always did; a function's own capabilities are checked against the capability lines either way.

The policy is loaded once at startup; change it by restarting the server.

A useful pattern is to size the policy from the app's own manifest: build the app, inspect the `caps=` fields in the `.hcr_manifest`, and grant exactly the capabilities the running boundary functions declare; then any future patch that reaches for more is caught.

### Per-role closures (`ACTIVATE6`)

A changed function's own capabilities have one blind spot: a patch that only *calls* an existing helper which already holds a capability. The patched function's own caps do not change, yet what it can reach does. For code that runs as a protocol role with a grant (`role Cons needs IO.Console`, see [Per-role grants]({{ site.baseurl }}/docs/choreography/#per-role-grants)), both gates also check the role's **full capability closure**: everything the role's code reaches, from the same solve the compiler's role-grant check runs.

The manifest `--compile-so` writes carries one line per granted role, with each capability's reach chain:

```
ROLE Stream.Cons caps=IO.Console,IO.FileWrite via=IO.Console:body>cons;IO.FileWrite:body>cons>save
```

`forge deploy hot` compares each role's closure with the saved baseline, exactly as it compares functions. A widened role stops the deploy unless `--grant-cap` covers it:

```
error: hot deploy would widen role Stream.Cons's capability closure
  running version caps:  IO.Console
  new version adds:      IO.FileWrite (reached: body → cons → save)
  A hot deploy may only narrow authority. To authorize this widening, re-run with:
      forge deploy hot --grant-cap IO.FileWrite
```

A role new to the baseline widens by its whole closure. A baseline written before per-role closures (no `ROLE` lines) makes this gate permissive for one deploy, with a note.

On the wire, a manifest with `ROLE` lines is deployed with the `ACTIVATE6` message: `ACTIVATE5`'s fields plus `role_caps:<Proto.Role>=<digest>;...` inside the signed line (one digest per role, sorted by role, the `cap_root` recipe over its closure) and an unsigned `roles:<Proto.Role>=<caps>;...` block. The server recomputes every digest from the block and refuses a mismatch, a signed role the block leaves out, or a role it adds unsigned (`ERR role_cap_tamper`), then checks the IO capabilities of every closure against `MARCH_DEPLOY_POLICY` (`ERR role_cap_policy Stream.Cons IO.FileWrite`), or of every role the policy's `serves` line names. A granted widening therefore still stops at a node whose policy forbids it. It is a new message rather than an extra field because an older server rebuilds the signed line without the role digests, so a signature check there would fail for a confusing reason. Today forge sends both shapes as `ACTIVATE7`, which adds a signed digest of the patch's bytes (see [Artifact integrity](#artifact-integrity-the-signature-covers-the-bytes)); a server that predates it refuses the deploy (upgrade it).

### Topology pools' derived capabilities

In a topology app (a project with a `topology.toml`), a pool whose `caps` the file leaves out gets them derived by the compiler from what its hook and roles reach. Derived does not mean unchecked: `forge deploy hot` compares each pool's derived caps with the ones recorded at the last completed deploy to the same environment (`.forge/deploy/<env>/derived.json`, `default` without `--env`; the same file `forge deploy` records), before it builds anything. A pool that gains a capability stops the deploy unless `--grant-cap` covers it:

```
error: hot deploy would widen pool edge's derived capabilities (D26)
  last deployed caps:    IO.Console   (the default environment)
  new version adds:      IO.FileWrite
  A hot deploy may only narrow authority. To authorize this widening, re-run with:
      forge deploy hot --grant-cap IO.FileWrite
```

A grant names the capability, not the pool: it authorizes it for every pool that widens to it. A pool new to the record widens by all its caps. With no record yet (the first deploy) the gate is permissive, with a note; when a record exists but the caps cannot be derived, the deploy stops rather than pass the gate blind. The record advances only when the deploy completes on every server. `forge build` prints a warning for each pool that widens relative to any environment's record. See [Topology → Derived capabilities and the widening gate]({{ site.baseurl }}/docs/topology/#derived-capabilities-and-the-widening-gate).

### `--grant-cap`

`--grant-cap <CAP>` is repeatable and subsumption-matched: `--grant-cap IO.FileSystem` authorizes a widening to the narrower `IO.FileWrite`. The granted capability becomes part of the deployed function's own signed capability set, so it can't be stripped or altered without breaking the signature; the server's audit log records who deployed which function, when, and with which capability set, so a widening is always traceable back to the person who authorized it.

Each `ACTIVATE` appends one JSON line to `$MARCH_AUDIT_LOG` (default `${XDG_DATA_HOME:-$HOME/.local/share}/march/audit.jsonl`) with `ts`, `type` (`activate`, `restore` for a replay at start, `topology` for a topology push, `drain` for a `DRAIN` request, `release` for a release accepted or refused), `fn`, `impl_hash`, `signer`, `cas_hash`, `caps`, `cap_root` and `result`, plus `roles` (the role closures as received) for `ACTIVATE6`, and `accepted_unproved` on an `ok` line whose image was built with `--accept-unproved` (the deploy-gate laws it went out without a proof; see [Contracts across versions](#contracts-across-versions)). `caps` is the deploy's capability list (`[]` for a capless artifact) and `cap_root` its signed root; both are `null` for deploys over pre-v4 protocols, which carry no capability data. They are recorded as received, so on a rejected request (`err_sig`, `err_cap_tamper`) they show what the request claimed, not a verified set. To find when a node last gained a capability: `jq -c 'select(.result == "ok" and (.caps // [] | index("IO.Network")))' audit.jsonl | tail -1`.

```sh
forge deploy hot --grant-cap IO.FileWrite --grant-cap IO.Process --so v2.so
```

The grant only relaxes the client-side monotonicity gate. It does **not** override a node's `MARCH_DEPLOY_POLICY`; as the worked example shows, a granted widening still gets `ERR cap_policy` at a node that forbids the capability.

### `migrate_state` must be IO-free

A `migrate_state` function runs in the migration window, between the last message sent to the old code and the first handled by the new code, a moment where doing IO (or panicking) has dangerous ordering and partial-failure semantics. The compiler enforces this: a `*_migrate_state` function with a body that performs any IO builtin or `extern` call is a compile error.

```
migrate_state must be IO-free
MyApp.Counter.counter_migrate_state calls capabilities that need IO.FileWrite.
migrate_state runs during the hot-migration window, before user messages.
hint: move side effects into a normal handler that runs after migration completes.
```

The check uses the migration function's **own** effects: a `migrate_state` in a module that declares `needs IO.Console` for its *handlers* still compiles cleanly, because the migration body itself does no IO.

### Threat model: what the gates do and do not prove

The capability manifest is **self-reported by the compiler**. The node's checks prove
*integrity* (each function's declared capability set is hashed into a `cap_root`, and
that hash is part of what's signed, so an attacker modifying the capability list in
transit (without the signing key) produces a hash mismatch that aborts with
`ERR cap_tamper`) and *policy* (the declared authority fits the node), but **not
truthfulness** (that the compiled machine code actually stays within the declared caps;
the server cannot recompute effects from a shared object).

- **Defends against:** accidental authority creep by a well-behaved toolchain (the common case); operator error shipping the wrong build to a restricted node; a compromised deploy *pipeline* that still builds with the real compiler; tampering with the capability set in transit.
- **Does not defend against:** a party holding the signing key who hand-crafts a `.so` with a lying manifest. Capability admission is authorization *on top of* authentication, a defense-in-depth layer, not a sandbox. For stronger guarantees, combine it with OS-level confinement of the reload server.

A policy constrains what *hot-patched* functions may do; it does not retroactively constrain the trusted base binary the operator already deployed.

### Backward compatibility

Every gate is opt-in and additive. A pre-capability artifact (no capability fields in its manifest) deploys with permissive admission and a one-line note. A manifest without `ROLE` lines is admitted exactly as before (forge sends it as `ACTIVATE7`, which only adds the bytes' digest). A node with no `MARCH_DEPLOY_POLICY` allows everything, exactly as before. Deploying capability-aware code to a server that predates node admission fails fast with an actionable message rather than silently downgrading; re-run with `--no-cap-gate` if you intentionally want the legacy path.

---

## Sequenced releases: no replayed requests

A signed line on its own proves who wrote it, not when. Without more, a signed `ACTIVATE`, `TOPOLOGY` or `DRAIN` recorded once could be sent again later: to roll a function back to an old version, re-push an old placement, or repeat a drain. So forge wraps every signed line it sends in a **release**:

```
SEQ <seq> <id> <signature> <signed line>
```

signed over `SEQ <seq> <id> <signed line>` with the deploy key. The inner line keeps its own signature, checked as before. One `forge` invocation is one release: `<id>` is random (32 hex digits), and `<seq>` is the time in milliseconds, or one more than the node's current release if that is higher. The node keeps the highest release it has accepted, its **head**, in a file of its own next to the persisted state (`<state dir>/release`), so a restart, `MARCH_HCR_NO_REPLAY` or a different build on the socket does not forget it:

| The release | The node |
|---|---|
| newer than the head | accepts it, and it becomes the head (gaps are fine: a node a deploy did not touch never saw that release) |
| the head itself | accepts it: a retry, or the next line of the same deploy |
| the head's number with another id | refuses it, `ERR release_fork head:<n>:<id>`: two deploys chose the same number |
| older than the head | refuses it, `ERR stale_release head:<n>` |

Once a node holds a release, or when it was started with `MARCH_HCR_REQUIRE_RELEASE=1`, a signed line that is not wrapped is refused with `ERR release_required`, so a line recorded before the node saw its first release cannot be replayed either. `RELEASE_HEAD` answers `HEAD <seq> <id>` (`HEAD 0 -` before any release, with ` required` appended under `MARCH_HCR_REQUIRE_RELEASE`); forge asks it once per connection and sends unwrapped lines only to a server that does not know the request. Every release a node accepts or refuses is audited (`type` `release`).

forge reports a refusal in words: a stale release means another deploy reached the node first, or this machine's clock is behind; a fork means two deploys ran at once. Re-run the deploy either way.

---

## Artifact integrity: the signature covers the bytes

A patch reaches a node in two parts: its bytes go into the node's artifact store (the CAS, `~/.march/cas/artifacts/`, under the compiler's compilation hash), and a signed `ACTIVATE` line names them. The CAS is **not** a trust boundary. Anyone who can reach the reload socket, or the control API of a candidate, can write it with `CAS_PUT`, and the compilation hash is a hash of the build's inputs, not of the bytes stored under it. Until `ACTIVATE7` nothing signed the bytes, so whoever could write a node's CAS chose what an operator's signed line loaded, constructors included (review `specs/progress/2026-10-04-dd12-review-cas-artifact-unverified.md`).

`ACTIVATE7` carries the BLAKE3 of the `.so` file's bytes, `so_blake3:<hex>`, **inside** the signed line (between `epoch:` and `cap_root:`); otherwise it is `ACTIVATE5`, or `ACTIVATE6` with the role blocks. Before it maps anything, the node reads the artifact once, hashes exactly the bytes it read, and copies them to a directory of its own (`<state dir>/loaded/<so_blake3>.so`, mode `0700`, written by no request). It loads that copy only if the bytes are the signed ones, so a file replaced between the check and the load changes nothing. Bytes that do not match are refused with `ERR artifact_digest`, audited as `err_artifact_digest`, and none of their code runs.

The CAS verbs take the digest as well, so forge spots a bad copy before it activates anything:

| Request | Answer |
|---|---|
| `CAS_CHECK <hash> so_blake3:<hex>` | `PRESENT` only if the stored bytes hash to `<hex>`, so forge uploads a stale or substituted artifact again |
| `CAS_PUT <hash> <size> so_blake3:<hex>` | `ERR digest_mismatch` (nothing stored) for bytes that do not hash to `<hex>` |

Both still accept the old form without the digest. Someone who can write the CAS can still replace an artifact after forge uploads it; the deploy then fails with `ERR artifact_digest`, and forge says so. That is a delay, not a forgery: no unsigned code runs (design D37).

Older lines (`ACTIVATE` through `ACTIVATE6`) sign no digest of the bytes. A node that holds a release, or runs with `MARCH_HCR_REQUIRE_RELEASE=1`, refuses them with `ERR artifact_digest_required`, wrapped in a release or not, and does not replay such entries from its patch stack (see [Restart durability](#restart-durability)). Before its first release a node still accepts them, as before. forge sends `ACTIVATE7` for every capability-aware deploy. `--no-cap-gate` still sends the legacy `ACTIVATE3`, so it only works against a node that accepts unbound lines.

The reload socket itself is owner-only (`0600`, set before it accepts connections, whatever the umask the node inherited), and a peer whose uid is not the node's (or root's) is disconnected.

---

## Restart durability

A restarted server comes back on the code it was running, without a redeploy and before `main` runs (so before a node opens any offer). The reload server keeps a **patch stack** on the host, under its CAS root next to `next_epoch`:

```
~/.march/cas/hcr_state/<16 hex of blake3(socket path)>/state
```

It holds every activated function's signed message and signature in activation order (a deploy's functions share one sequence number), a digest of the base build it patches, a digest of the code actually running (`manifest`), and the digest of the last topology pushed. It is rewritten with a temporary file and a rename after every deploy.

At start, before `march_reload_server_start` returns, the server replays it:

- Each entry's **signature is verified again** from the stored signed line with the key baked into the binary.
- An invalid entry (bad signature, missing artifact, unknown function) is audited (`"type":"restore"`, `"result":"err_restore_sig"` and so on). Its **whole deploy batch and every later batch are refused**: a later migration may depend on the missing version. The server retains the verified prefix, or the base build if no complete batch precedes the failure. A malformed stack line prevents all replay because its batch dependencies cannot be established.
- An `ACTIVATE7` entry's artifact must **still hash to its signed digest** (`err_restore_digest` otherwise), and is loaded through the same verified copy as a live deploy, so bytes replaced in the CAS while the node was down are not replayed. An entry written before `ACTIVATE7` has no signed digest to check its bytes against: it is replayed only where such a line would still be accepted live (no release held, no `MARCH_HCR_REQUIRE_RELEASE`), and refused otherwise (`err_restore_no_digest`), stopping replay at that batch.
- Every complete deploy batch is republished in its original order, including signed migration flags and the helper functions that migrations may call. This preserves multi-hop state conversions for actors initialized by the base program after restart. Successfully replayed history remains in the rewritten stack; a refused suffix is removed. If bounded version or epoch capacity cannot retain that history, startup exits with an explicit full-release/restart diagnostic instead of dropping migrations or continuing on an incomplete chain.
- A **different build** on the same socket (its baseline digest differs) does not replay the stack: patches of one build are not patches of another. The file is set aside as `state.base-changed`.
- `MARCH_HCR_NO_REPLAY=1` starts from the base binary and sets the stack aside as `state.no-replay`: the escape hatch for a patch that breaks the boot.

`VERSIONS` then shows the hot versions as before, and `VERSIONS_DETAIL` gains a line saying what the start restored:

```
RESTORED entries:1 skipped:0 mode:replayed stack:1 manifest:<hex> topology:<hex>
```

(`mode` is `none` on a first start, `replayed`, `off` under `MARCH_HCR_NO_REPLAY`, or `base_changed`.) The state is keyed by the socket path because the CAS root is shared by every March program of a user; the socket names the service.

**Compaction.** A host that boots its base binary and then republishes a long stack boots slowly and runs code no single build produced. `COMPACT` reports the stack's size, and `forge hot-reload status` prints it per node:

```
Patch stack: 3 persisted patches over 2 deploys (2 functions), 1 artifact, 1.2 MiB in the CAS
```

When it grows long, `forge deploy --compact --env <env>` rebuilds each build's base image from the current version, restarts its hosts onto it (the new base build makes the server set the old stack aside) and removes what was set aside; each node then reports an empty stack. With `[hot-reload] compact_after = N` in `forge.toml`, `forge deploy` does this by itself for a build whose nodes report a stack longer than `N`.

---

## Current limitations

Hot reload swaps native code in a live process, and that has failure modes a restart
does not. The Phase 0 soundness spike (2026-10-13,
[`specs/progress/2026-10-13-hcr-phase0-spike.md`](https://github.com/march-language/march/blob/main/specs/progress/2026-10-13-hcr-phase0-spike.md))
ran the shipped `.so` patch model under AddressSanitizer and found three ways a swap
corrupted or leaked memory: a parameter changing from borrowed to owned (use-after-free),
a patch introducing a new closure shape (leaked captures), and a reclaimed patch image
being unmapped under live closure code (crash). All three were fixed the same day. The
spike's verdict was to keep the shipped native-patch model and not build an in-server
JIT on top of it.

These are still open:

- **Long-running frames retain old versions.** A `main` loop that never returns,
  or an escaping closure, can prevent version reclamation. Baseline main keeps its
  baseline routing epoch even when saved patches are restored on restart.
- **Sandboxed reload writes need `IO.FileWrite`.** Without it, the compiler warns
  and the sandbox rejects artifact and persistence writes. Read-only observation
  remains available.
- **Old patch images stay mapped.** A reclaimed version's `.so` is never unloaded, so a
  long-lived node keeps one mapped image per deploy until it restarts.
  ([todo](https://github.com/march-language/march/blob/main/specs/todos/2026-10-13-hcr-unload-unreachable-patch-images.md))

## See also

- [Capabilities]({{ site.baseurl }}/docs/capabilities/): the capability system behind capability-safe deploys, including the full IO capability hierarchy
- [Actors]({{ site.baseurl }}/docs/actors/): the actor model hot reload builds on
- [Supervision Trees]({{ site.baseurl }}/docs/supervision/): combine hot reload with fault-tolerant supervision
- [Refinement Types]({{ site.baseurl }}/docs/refinement-types/): the type-level system behind `@invariant` checking
- [Tooling]({{ site.baseurl }}/docs/tooling/): `forge` build tool reference
- [Choreography]({{ site.baseurl }}/docs/choreography/#changing-a-protocol): what a protocol change means for sessions in flight
- [Observing a running node]({{ site.baseurl }}/docs/observe/): `EPOCHS`, `WHICH` and `SOURCE` on a node after a deploy
- [Topology]({{ site.baseurl }}/docs/topology/): the pools, hosts and control plane `forge deploy` plans against
