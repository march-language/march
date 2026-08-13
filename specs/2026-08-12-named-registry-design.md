# Named process registry — design

**Date:** 2026-08-12 (revised same day, see §4)
**Status:** design, not yet implemented
**Todo:** `specs/todos/2026-08-12-actor-named-registry.md`
**Depends on:** `specs/todos/2026-08-12-vault-toward-ets-semantics.md`

## 1. The problem, precisely

Supervision self-heals: a crashed child is respawned with backoff, and
`march_respawn_child` writes the new child's `pid_index` into the supervisor's
own state. That repairs the **inside** of the tree.

It does nothing for anyone **outside** it. A `Pid` is a handle to one
*incarnation*. After a restart every external holder has a handle to a dead
actor, and:

- `send` to it returns `None` — correct, and useless; there is no next step;
- `get_cap` reports the capability stale via the epoch counter — detection with
  no recovery;
- nothing maps "the thing that plays this role" to "the incarnation currently
  playing it".

The healing is invisible from outside. Every comparable runtime reaches for the
same fix: **hold a name, resolve it at use time.**

## 2. What we are copying

Elixir's `Registry` (verified against v1.20.3 source) is the closest model, and
it is **built on ETS** rather than on a bespoke structure:

- key tables are `:set` / `:ordered_set` / `:duplicate_bag`, `:public`, with
  **`read_concurrency: true, write_concurrency: true`**;
- **lookups read ETS directly from the calling process** —
  `:ets.lookup_element(key_ets, key, 2)`, no GenServer round-trip;
- partitions are chosen by `:erlang.phash2(term, limit)` to cut contention;
- **a second, pid-keyed table is the reverse index**: cleanup is
  `entries = :ets.take(ets, pid)`, then the key entries are removed;
- cleanup is triggered by **links and EXIT signals** (`Process.link`,
  `handle_info({:EXIT, pid, _reason}, …)`), not monitors.

Two things follow that shaped this revision. First, the layering — *general
in-memory table + registry as a library on top* — is the proven factoring, not
an accident. Second, the pid→keys reverse index is not something a KV store
lets you avoid; the reference implementation builds one too.

We are **not** copying Orleans-style virtual activation (placement, activation
lifecycle, single-activation guarantees). That is a much larger commitment and
is out of scope here, though nothing below forecloses it.

### Relationship to the existing distributed registry

`stdlib/global_registry.march` is a CRDT over names — `Map(String, Entry)` with
`node_id`, `pid`, a `VectorClock` and tombstones, plus `merge` / `root_hash` /
`diff_entries` for anti-entropy. It is pure data: it stores a `pid : Int` and
cannot reach a live process.

This design is its **local counterpart**. Keep the vocabulary aligned —
`register` / `unregister` / `lookup` / `names` — and keep names `String`, which
is what `global_registry` keys on, so the eventual `:global` variant is a
routing decision rather than a second API.

## 3. Architecture

Three layers, mirroring Elixir's:

1. **Storage: Vault.** Two tables — `name → pid` and `pid → names` (the reverse
   index, per §2). Vault is already a C-backed, process-global, ETS-like table
   with per-table locking and RC'd values (`runtime/march_extras.c`).
2. **Policy: stdlib.** `Actor.register` / `whereis` / `unregister` live in
   March, over those tables. Testable, and extensible to duplicate keys later
   without touching the runtime.
3. **Cleanup trigger: the runtime.** `do_actor_death` drops the dying actor's
   entries through Vault's C API.

Layer 3 is the deliberate divergence from Elixir — see §6.

## 4. Why not a bespoke C table (revised)

The first draft of this spec proposed a dedicated hash table beside
`g_actor_tbl`, on the grounds that a "registry actor" would cost a message
round-trip per lookup, be a single-actor bottleneck, and be unreachable from
`do_actor_death` during teardown.

Those objections are all true of an **actor** and none of them are true of
**Vault**, which is not one: it is C-backed, has a per-table mutex rather than a
single global lock, and its `march_vault_drop` is a plain C function callable
straight from `do_actor_death`. The original rationale over-generalised from
"not an actor" to "must be a new structure."

The real objections to Vault-as-it-stands are narrower and, importantly,
**fixable properties of Vault** rather than reasons to build a parallel
structure: read concurrency, value typing, and the capability requirement.
They are specified in
`specs/todos/2026-08-12-vault-toward-ets-semantics.md`, and §5/§7 below give
the registry's stake in each. Building a second hash table to dodge three
fixable properties would leave Vault's own users with all three.

## 5. What Vault needs first

| Property | Vault today | Needed | Whose problem |
|---|---|---|---|
| Concurrent reads | per-table mutex on every `get` | ETS `read_concurrency` equivalent | **Registry's**: the guidance is "resolve at use", so lookups land on the send path — which Task 10 deliberately took *off* a mutex |
| Write concurrency | one mutex per table | partitioned/sharded buckets | Registration storms during a restart wave |
| Value typing | `Option(ptr)`, erased | typed handles | **Registry's**: a mistyped read followed by `send` dereferences garbage as an actor record |
| Capability | every op needs `IO.Mut` | see §7 | **Registry's**: name resolution would drag a mutation capability into every module |

The first two are independently justified: Vault is documented as *"shared
across all actors without message passing"*, and `docs/overload-resilience.md`
points readers at Vault-style tables for rate limiting — a read-heavy workload
where a mutex per read is already a wart.

## 6. Death cleanup, and why we diverge from Elixir here

Elixir cleans up on EXIT signals because that is what a BEAM *library* has.
March has neither working links (`specs/todos/2026-08-12-links-and-exit-signals-unreachable.md`
— `link` has no typechecker entry, so no program can call it) nor
reason-carrying monitors (`specs/todos/2026-08-12-monitor-down-carries-no-reason.md`).
A faithful port is therefore blocked on two other gaps.

But we control the runtime, so we can do better than a library could:
**`do_actor_death` drops the entries directly.**

This is not merely expedient. Elixir's lookup can return a **dead pid** in the
window between process death and the partition processing the EXIT — documented
and lived with. A runtime hook closes that window entirely.

Coupling is kept minimal: the runtime learns about one well-known table, not
about registries. Concretely, `do_actor_death` looks up the dying actor in the
reverse table, drops each name from the forward table, then drops the reverse
entry.

**Ordering matters.** Retire the names **before** monitor Down notifications
fire, or a watcher woken by a Down that immediately calls `whereis` sees the
dead incarnation. That constraint lands in the same function as the
Down-with-reason work — do them together.

## 7. The capability question

`IO.Mut` on every Vault op is the sharpest objection to this whole design: it
would make `Actor.whereis(name)` require `needs IO.Mut` in every module that
resolves a name — i.e. essentially every module in an actor program. Resolving
a name is not mutation, and the capability ceiling is a headline March feature.

### The insight: the handle already *is* the capability

March has value-carried authority: `fn main(_c : Cap(IO.Console))` takes the
grant as a parameter, and `get_cap(pid)` mints an epoch-checked actor
capability. A `VaultTable` handle has exactly that shape — it is unforgeable
and obtainable only from a naming operation.

That suggests splitting Vault's surface by **where authority is minted**, not
by read-vs-write:

- **Naming ops mint authority from a string.** `vault_new(name)` and
  `vault_whereis(name)` turn "anyone who can spell `rate_limits`" into access.
  That is precisely the ambient-authority pattern capabilities exist to
  control — the same shape as `File.open(path)` needing `IO.FileRead`. **These
  keep a capability requirement.**
- **Data ops act on a handle you were given.** `get` / `set` / `drop` /
  `update` / `size` / `keys` require **no ambient capability**, because
  possessing the handle *is* the authority — and it is strictly more precise
  than `needs IO.Mut`, which says "this module touches shared state" without
  saying *which*.

### Attenuation: split the handle, not the capability

For "you may look up but not mutate", derive a read-only view —
`Vault.readonly(t) : VaultRead` — rather than splitting `IO.Mut`. That is
ocap attenuation, it composes with passing handles across module boundaries,
and it is finer-grained than any capability split could be (per-table, not
per-program).

A `IO.Mut.Read` / `IO.Mut.Write` split under `IO.Mut` is the alternative, and
the lattice already has the precedent (`IO.FileRead`/`IO.FileWrite` under
`IO.FileSystem`, `lib/caps/cap_lattice.ml`). It is worth doing *for the naming
ops* — `whereis` is read-only, `new` creates — but it does not solve the
annotation burden on data ops the way handle-as-authority does.

### The honest cost

Dropping the capability from data ops loses an audit signal at the *use* site:
a module that mutates a table it was handed declares nothing. The mitigation is
that authority remains auditable at the **boundary** — some module named the
table and declared the capability, and handles flow explicitly through
signatures. That is the standard ocap trade-off; it should be stated in the
capability docs rather than discovered.

A second, subtler cost: a read of shared mutable state is non-deterministic
(it observes another actor's writes). If `needs` is read partly as a purity
signal, removing it from `get` loses that. See §12.

### What the registry does about it

The registry sidesteps the question entirely on its hot path: **the runtime
owns the well-known registry tables**, and `actor_whereis` is a builtin that
reaches them in C. No March-level naming call happens, so `Actor.whereis`
carries **no capability at all** — regardless of how §7 is resolved for Vault
generally. `Actor.register` is the op that grants reachability-by-name and is
the one worth a capability, if any.

This is why layer 2 is stdlib-over-builtins rather than stdlib-over-`Vault.*`:
the data lives in Vault (so introspection, tooling and the reverse index come
free), while the access path stays capability-clean.

## 8. Semantics

**Uniqueness.** One actor per name (Elixir's `:unique`). A second `register`
for a live name fails rather than overwriting — silently stealing a name is a
3am bug. Duplicate/group registration is out of scope: `stdlib/pubsub.march`
already covers fan-out.

**Several names per actor** is permitted — nothing in the structure needs the
restriction, and the reverse index makes cleanup cheap either way.

**Registering a dead actor** fails. **`whereis` of a name whose actor has since
died** returns `None`: check liveness (`fields[3]`) at lookup rather than
trusting the entry, since cleanup and lookup race by nature.

## 9. Surviving a restart — the actual point

`march_respawn_child` already runs on every restart and knows the crashed
child's identity. Have it read the names held by the crashed incarnation (from
the reverse table, captured **before** cleanup retires them) and register the
replacement under the same names.

This needs **no syntax change** to `supervise` blocks: a child that was
registered stays registered across restarts; a child that was never registered
is unaffected.

Sequencing is deliberate. Cleanup retires the names during `do_actor_death`,
and the restart may be delayed by up to ~3.2s of backoff. During that window
the name correctly resolves to `None` — the actor genuinely does not exist yet.
Callers must handle it; this is the honest signal that the service is
mid-restart, and strictly better than today's Pid that looks fine and silently
drops.

## 10. Surface API

Builtins (each needs all four sites — typecheck / defun / llvm_builtins / eval
— per the `compiler-builtin` skill):

| Builtin | Type | Capability |
|---|---|---|
| `actor_register` | `String -> Pid(a) -> Bool` | see §7 |
| `actor_unregister` | `String -> Bool` | see §7 |
| `actor_whereis` | `String -> Option(Pid(a))` | none |
| `actor_registered` | `Unit -> List(String)` | none |

Stdlib wrapper in `stdlib/actor.march`: `Actor.register/2`, `Actor.unregister/1`,
`Actor.whereis/1`, `Actor.registered/0`.

`Actor.whereis` returning `Option` is load-bearing — it forces the caller to
handle the mid-restart window from §9.

Deliberately **not** proposed: making `send` accept a name. Overloading `send`
hides a fallible lookup inside an operation whose failure mode is already
subtle (`None` for a dead actor); the explicit form keeps the two
distinguishable. `cast_named` / `call_named` conveniences can follow if the
explicit form proves noisy.

## 11. Test plan

- **The restart witness** — the whole feature: register a supervised child,
  kill it repeatedly, reach it by name after every restart *from a holder that
  never sees the new Pid*. Native golden, since supervision is where the two
  backends have historically diverged.
- **Death cleanup**: `whereis` returns `None` after a kill with no restart.
- **Name reuse**: register → kill → register a *different* actor under the same
  name succeeds.
- **Interpreter parity**: pinned by golden. This is exactly the class of
  divergence that hid compiled `mailbox_size` returning the Down count.
- **Churn cost**: extend `bench/actors/spawn_churn.march` with registrations —
  death cleanup must stay O(names held), not a table walk per death (the
  scenario kills 40 000 actors).
- **Send path unaffected**: the fan-in scenario in `scripts/actor-load.sh` must
  not regress; the registry must put no lock where `send` runs.

## 12. Open questions

1. **Does `whereis` check liveness, or is the retire-on-death race tight
   enough?** Proposed: check — one load of `fields[3]` on a path that is not
   per-message hot.
2. **Is a read of shared mutable state an effect?** §7 proposes data ops need
   no capability. If `needs` is also a purity signal, that loses information.
   Decide before the split ships, since it governs all of Vault.
3. **Should the supervisor re-register names for a child it did not itself
   register?** §9 says yes. The alternative needs a child-spec field, worth
   revisiting if specs grow anyway for restart types
   (`specs/todos/2026-08-12-supervisor-restart-types-and-child-specs.md`).
4. **Partitioning:** does the registry want its own partitioned tables from the
   start, or is one table with concurrent reads enough until measured?
5. **Distributed seam:** should a local registration announce into
   `global_registry` automatically? Proposed: no, not implicitly — design the
   bridge when the distributed plane
   (`specs/todos/2026-08-11-actor-hardening-distributed-plane.md`) is picked up.
