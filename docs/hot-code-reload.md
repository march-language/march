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

## Next Steps

- [Actors]({{ site.baseurl }}/docs/actors/) — the actor model hot reload builds on
- [Supervision Trees]({{ site.baseurl }}/docs/supervision/) — combine hot reload with fault-tolerant supervision
- [Refinement Types]({{ site.baseurl }}/docs/refinement-types/) — the type-level system behind `@invariant` checking
- [Tooling]({{ site.baseurl }}/docs/tooling/) — `forge` build tool reference
