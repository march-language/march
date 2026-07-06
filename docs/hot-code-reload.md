---
layout: docs
title: Hot Code Reload
nav_order: 10.8
permalink: /docs/hot-code-reload/
---

# Hot Code Reload

March supports deploying new code to a running server **without restarting the process**. Actors keep running, their state is preserved, and new messages are handled by the new code — all while in-flight requests from the previous version complete normally.

This is useful in practice: no cold-start latency, no dropped connections, no TCP state reset, and no need to drain traffic before a routine code push.

---

## How it works

When you run `forge deploy hot`, the build tool:

1. Compiles your code to a shared library (`.so`) with content-addressed hashing
2. Diffs the function manifest against what the server has loaded
3. Uploads only the functions that changed (by content hash)
4. Sends each changed function to the server, signed with your ed25519 key
5. The server activates them atomically — new calls immediately use the new code

Actors that have a state schema change receive a `migrate_state` call before they handle any new messages, so they are never left in an inconsistent state.

Deploys are also **capability-gated**: each changed function carries its own IO capabilities, and both the deploy tool and the receiving node can refuse a patch that reaches for more authority than the running version — or the node's policy — allows. See [Capability-safe deploys](#capability-safe-deploys) below.

---

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
forge keygen --output ~/.march/deploy_key
# Writes: ~/.march/deploy_key (secret) and ~/.march/deploy_key.pub (public)
```

Put the public key in `forge.toml` and embed the secret key in the server binary at build time (or pass it as an environment variable — see your server's startup flags).

---

## Deploying

```sh
# Build and deploy in one step
forge deploy hot

# Deploy a pre-built artifact (e.g. cross-compiled for Linux)
forge deploy hot --so /path/to/my_app.so
```

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

If nothing has changed since the last deploy, forge detects this from the content hashes and exits cleanly:

```
No changes detected — server is already up to date.
```

---

## Capability-safe deploys

A hot deploy pushes new code straight into a running process: it's compiled, shipped to the server, loaded with `dlopen`, and starts handling requests. The ed25519 signature on each patch answers one question — *is this really from us?* It says nothing about a second, equally important one: *is this code allowed to do what it does?*

That gap is real. A patch you signed could call `file_delete`, open a network connection, or spawn a process — even if the version it replaces never touched the filesystem or the network at all. Signing proves **origin**, not **behavior**.

Capability-safe deploys add the missing check. March already knows each function's IO capabilities from compile time — its `needs` declarations plus the effects inferred from its body. A hot deploy carries those capabilities with it, and **two gates** decide whether the new code may run: one on your machine when you deploy, and one on the server when it activates.

### The unit of enforcement: per-activated-function caps

A hot deploy only re-activates the functions that **changed**. Each changed function carries **its own** inferred IO capabilities — the effects its own body requires — not the capabilities of the whole artifact.

This granularity matters. `--hot-reload` links the entire standard library into every patch, so a *whole-artifact* capability set would be dominated by the stdlib's footprint (filesystem, network, process, clock, …) and would be identical for every app — useless for a policy. Gating on the **changed function's own caps** is what makes the check discriminating: a patch that adds `file_write` to one function is caught precisely because that function now declares `IO.FileWrite`, regardless of what the rest of the linked code can do.

The trust boundary follows from this: the **base server binary is trusted** — you built and started it, with a policy. Each **hot-patched function** is the mobile code the gates govern.

### Two gates

1. **Monotonicity gate (deploy-time, on your machine).** *Monotonicity* just means the capabilities can only move in one direction. Across deploys, a function's set of capabilities may get *smaller* on its own, but it can't get *bigger* without your say-so.

   - **Dropping** a capability is always allowed — a function that used to write files and no longer does is strictly safer, so it deploys without ceremony.
   - **Adding** a capability is called a **widening** — for example, a function that gains the ability to write files, open a socket, or spawn a process that its running version didn't have. A widening **stops the deploy** and asks you to confirm it explicitly with `--grant-cap`.

   The point of this one-directional rule is that a routine code push can't quietly grant your running system new powers; the moment a patch reaches for more, you have to sign off on it by name.

2. **Node policy gate (activation-time, on the server).** If the node sets `MARCH_DEPLOY_POLICY`, the server refuses to activate any function whose capabilities exceed the node's policy — regardless of who signed it. This is enforced independently of the deploy tooling, so it holds even if the deploy pipeline is bypassed or compromised.

### A worked example

Start from a server whose reloadable handler only writes to the console:

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

**Step 1 — deploy v2 with no grant.** The monotonicity gate aborts on the client, before anything is uploaded:

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

Note the diagnostic names the exact capability *and* the specific function that introduced it. Widening the authority of a live system mid-flight is exactly the event an operator should consciously sign off on.

**Step 2 — grant the widening, but the node policy forbids it.** With `--grant-cap` you pass the deploy-time gate, the artifact uploads, and the server's policy gate rejects the activation:

```
$ forge deploy hot --grant-cap IO.FileWrite --so v2.so
Deploying 1 changed function(s)...
  granted widening: IO.FileWrite (via --grant-cap IO.FileWrite)
  Uploading artifact v2.so... Artifact uploaded.
  FAILED Server.handle: ERR cap_policy IO.FileWrite — deploy rejected by node capability policy
  Rolled back: 1 function(s) failed, server state unchanged.
error: 1 function(s) failed to activate
```

The node had the final say. The batch rolled back cleanly — the live system is unchanged.

**Step 3 — a node whose policy permits it.** Update the policy on the node and restart it (the policy is read once at startup):

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

The same signed patch is admitted here and rejected on the console-only node — per-node authority, enforced at the node.

### Configuring `MARCH_DEPLOY_POLICY`

`MARCH_DEPLOY_POLICY` is the path to a newline-delimited file of permitted capability paths. The check is **subsumption-aware**: listing a parent capability permits its children (`IO.Network` permits `IO.NetConnect`, `IO.NetConnect.TLS`, `IO.NetListen`, …). See [Capabilities]({{ site.baseurl }}/docs/capabilities/) for the full hierarchy.

```
# /etc/march/deploy-policy.txt — this node may only gain console + read-only + outbound TLS
IO.Console
IO.FileRead
IO.NetConnect.TLS
```

A node with this policy will never *admit a hot patch* that declares file-write, process-spawn, or foreign-FFI authority, regardless of signature. An empty policy file or an unset `MARCH_DEPLOY_POLICY` ⇒ permissive (all activations admitted) — the default, for backward compatibility. The policy is loaded once at startup; change it by restarting the server.

A useful pattern is to size the policy from the app's own manifest: build the app, inspect the `caps=` fields in the `.hcr_manifest`, and grant exactly the capabilities the running boundary functions declare — then any future patch that reaches for more is caught.

### `--grant-cap`

`--grant-cap <CAP>` is repeatable and subsumption-matched — `--grant-cap IO.FileSystem` authorizes a widening to the narrower `IO.FileWrite`. Each grant is folded into the deploy's signed payload and recorded in the audit log, so an authorized widening is tamper-evident and traceable to the signer.

```sh
forge deploy hot --grant-cap IO.FileWrite --grant-cap IO.Process --so v2.so
```

The grant only relaxes the client-side monotonicity gate. It does **not** override a node's `MARCH_DEPLOY_POLICY` — as the worked example shows, a granted widening still gets `ERR cap_policy` at a node that forbids the capability.

### `migrate_state` must be IO-free

A `migrate_state` function runs in the migration window, ahead of any pending user messages — a moment where doing IO (or panicking) has dangerous ordering and partial-failure semantics. The compiler enforces this: a `*_migrate_state` function whose own body performs any IO builtin or `extern` call is a compile error.

```
error: migrate_state must be IO-free
  MyApp.Counter.counter_migrate_state calls `file_write` (needs IO.FileWrite)
  migrate_state runs during the hot-migration window, before user messages.
  Move side effects into a normal handler that runs after migration completes.
```

The check uses the migration function's **own** effects — a `migrate_state` in a module that declares `needs IO.Console` for its *handlers* still compiles cleanly, because the migration body itself does no IO.

### Threat model — what the gates do and do not prove

The capability manifest is **self-reported by the compiler**. The node's checks prove *integrity* (the capability set was signed and has not been tampered with — a `cap_root` mismatch aborts with `ERR cap_tamper`) and *policy* (the declared authority fits the node), but **not truthfulness** (that the compiled machine code actually stays within the declared caps — the server cannot recompute effects from a shared object).

- **Defends against:** accidental authority creep by an honest toolchain (the common case); operator error shipping the wrong build to a restricted node; a compromised deploy *pipeline* that still builds with the real compiler; tampering with the capability set in transit.
- **Does not defend against:** a party holding the signing key who hand-crafts a `.so` with a lying manifest. Capability admission is authorization *on top of* authentication — a defense-in-depth layer, not a sandbox. For stronger guarantees, combine it with OS-level confinement of the reload server.

A policy constrains what *hot-patched* functions may do; it does not retroactively constrain the trusted base binary the operator already deployed.

### Backward compatibility

Every gate is opt-in and additive. A pre-capability artifact (no capability fields in its manifest) deploys with permissive admission and a one-line note. A node with no `MARCH_DEPLOY_POLICY` admits everything, exactly as before. Deploying capability-aware code to a server that predates node admission fails fast with an actionable message rather than silently downgrading — re-run with `--no-cap-gate` if you deliberately want the legacy path.

---

## Actor state migration

When an actor's state record changes between deploys, the server needs to know how to upgrade the existing in-memory state of every live actor. You provide a `migrate_state` function:

```march
mod MyApp do

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

The naming convention is `<actor_name_lowercase>_migrate_state`. The parameter type is the **old** state shape; the return type is the **new** state shape. Every live actor is migrated before it processes any further messages.

---

## Compatibility annotations

Without a `migrate_state` function, `forge deploy hot` enforces strict compatibility: if the state schema changed, the deploy is rejected. You can relax this with `@compat`:

```march
-- Default: any schema change requires migrate_state
@compat(full)
actor Counter do ... end

-- Allow adding fields without migrate_state (new actors get init; old actors keep their field values)
@compat(forward)
actor Counter do ... end

-- Skip schema checking entirely (dangerous — use only for rapid iteration)
@compat(any)
actor Counter do ... end
```

| Policy | What's allowed without `migrate_state` |
|---|---|
| `full` (default) | Nothing — any change requires migration |
| `forward` | Adding new fields (existing actors use default values from `init`) |
| `any` | Any change — no migration check |

For production deployments, `full` with explicit `migrate_state` is safest. It means every state transition is intentional and reviewed.

---

## Verifying migration soundness with `@invariant`

If your actor has a state invariant — a condition that must hold for every live actor — you can annotate it and the compiler will **prove** that your `migrate_state` function preserves it before the deploy is allowed through.

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

Both satisfy `len(history) == count`. The compiler verifies this using an SMT solver — no input can slip through.

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

---

## Full forge.toml reference

```toml
[hot-reload]
ssh_host   = "my-server"        # required: SSH host (alias or hostname)
socket     = "/tmp/app.sock"    # required: Unix socket path on the remote
public_key = "base64key="       # required: ed25519 public key (base64)
```

All three fields are required. The deploy uses `ssh` from the system PATH; your `~/.ssh/config` aliases and identity files are respected.

---

## Deploying signature changes

When a function's signature changes between deploys — for example, `B.foo` gains a new parameter — the server needs to know that every existing caller of the old signature is also being replaced in the same deploy batch. Otherwise old callers would pass the wrong number or type of arguments to new code.

`forge deploy hot` enforces this automatically via the **coordinated upgrade gate**. The compiler records which boundary functions call each export in the `.hcr_manifest` sidecar (`callers:` field). The server stores this caller set per slot at activation time. On the next deploy, when it detects a `sig_hash` change for `B.foo`, it checks whether every server-recorded caller is included in the current deploy batch:

- **All callers covered:** the deploy proceeds with a message like:
  ```
  Coordinated upgrade: sig_hash changed, all callers covered.
    B.foo: old sig abc123 → new sig def456
    A.Worker_dispatch: present in deploy (impl_hash changed) ✓
  ```

- **A caller is missing:** the deploy is rejected with a named-caller error:
  ```
  error: B.foo signature changed but the following callers are not included in this deploy:
    A.Worker_dispatch calls B.foo — must also be updated in this batch
  hint: add Module A to the deploy batch or use expand-contract:
    1. Add B.foo_v2 alongside B.foo, update A to call B.foo_v2, deploy together
    2. In a later deploy, remove B.foo
  ```

If neither module in a pair has ever been deployed with caller tracking enabled (e.g. they were compiled separately before this feature existed), the gate conservatively allows the deploy — the caller set is empty, so there are no recorded callers to check.

---

## Independent deploy pace (epoch-tagged dispatch)

The coordinated upgrade gate works well when you can batch all callers into one deploy. But sometimes you want to deploy `B.foo` v2 today and migrate the callers next sprint — without blocking the deploy or risking ABI mismatches.

**Epoch-tagged dispatch** (Phase 9) makes this safe. The compiler bakes a per-file-static epoch cell (`@__march_hcr_epoch`) and an exported init function (`@__march_init(i32)`) into every `.so` output. The reload server assigns a monotonic epoch number per deploy batch via the `GET_EPOCH` protocol command and stamps it into the loaded `.so` by calling `__march_init` after `dlopen`.

At runtime, boundary call sites call `march_dispatch_enter_gen(NAME_ID, epoch, &v)` instead of the simpler `march_dispatch_enter`. This function routes to the **newest ring slot whose epoch ≤ the caller's epoch**, rather than always picking the newest slot. The effect:

- Old deployed `A.so` (epoch 5) calls `B.foo` → gets the `B.foo` that was active at epoch 5 (old version)
- New deployed `A.so` (epoch 7) calls `B.foo` → gets the newest `B.foo` (new version)

Old callers naturally see the old function until they are redeployed. No coordination, no batching required.

When Phase 9 is active, the Phase 8 gate downgrades from a hard error to an advisory warning — the deploy proceeds regardless, because epoch routing guarantees old callers cannot reach new code.

The deploy flow gains one step: forge calls `GET_EPOCH` to receive the batch's epoch number, which the server increments atomically for each deploy. If the server does not support `GET_EPOCH`, forge falls back to epoch 0 and the Phase 8 gate applies as normal.

### Compatibility table

| Server supports epoch | Forge supports epoch | Result |
|---|---|---|
| No | No | Phase 8 gate only |
| Yes | No | Phase 8 gate (forge never calls GET_EPOCH) |
| No | Yes | Forge calls GET_EPOCH → ERR → epoch 0 → Phase 8 gate |
| Yes | Yes | Full Phase 9: epoch-tagged routing, gate becomes advisory |

---

## Next Steps

- [Capabilities]({{ site.baseurl }}/docs/capabilities/) — the capability system behind capability-safe deploys, including the full IO capability hierarchy
- [Actors]({{ site.baseurl }}/docs/actors/) — the actor model hot reload builds on
- [Supervision Trees]({{ site.baseurl }}/docs/supervision/) — combine hot reload with fault-tolerant supervision
- [Refinement Types]({{ site.baseurl }}/docs/refinement-types/) — the type-level system behind `@invariant` checking
- [Tooling]({{ site.baseurl }}/docs/tooling/) — `forge` build tool reference
