# Named process registry — design

**Date:** 2026-08-12
**Status:** design, not yet implemented
**Todo:** `specs/todos/2026-08-12-actor-named-registry.md`

## 1. The problem, precisely

Supervision self-heals: a crashed child is respawned with backoff, and
`march_respawn_child` writes the new child's `pid_index` into the supervisor's
own state. That repairs the **inside** of the tree.

It does nothing for anyone **outside** it. A `Pid` is a handle to one
*incarnation*. After a restart every external holder has a handle to a dead
actor, and:

- `send` to it returns `None` (correct, and useless — there is no next step);
- `get_cap` correctly reports the capability as stale via the epoch counter —
  again detection with no recovery;
- nothing maps "the thing that plays this role" to "the incarnation currently
  playing it".

So the healing is invisible from outside. The fix every comparable runtime
reaches for is the same: **hold a name, resolve it at use time.**

## 2. What we are copying, and what we are not

- **BEAM** — `register(Name, Pid)` / `whereis(Name)`, plus `{via, Module, Term}`
  so a gen_server can be addressed through any registry. Names are atoms and
  the table is global to the node. Elixir's `Registry` adds unique-vs-duplicate
  keys, arbitrary term keys, and automatic cleanup on death.
- **Akka** — the actor *path* is the stable identity; an incarnation is
  addressed through it.
- **Orleans** — the strongest version: you never hold a reference at all, you
  address a grain by identity and the runtime activates one on demand.

We copy BEAM/Elixir's shape: an explicit registry with automatic cleanup.
Orleans-style virtual activation is a much larger commitment (placement,
activation lifecycle, single-activation guarantees) and is **not** proposed
here — but note the design below does not foreclose it.

### Relationship to the existing distributed registry

`stdlib/global_registry.march` already exists and is a *CRDT over names* —
`Map(String, Entry)` where `Entry` carries `node_id`, `pid`, a `VectorClock`
and a tombstone flag, with `merge`, `root_hash` and `diff_entries` for
anti-entropy between nodes. It is a pure data structure: it stores a `pid : Int`
but has no way to reach a live process.

This design is deliberately its **local counterpart**, and the two compose:
the local registry answers "which live actor on *this* node has this name",
`global_registry` answers "which node claims this name, and whose claim wins".
Keep the vocabulary aligned — `register` / `unregister` / `lookup` / `names` —
so the eventual `:global` variant is a routing decision rather than a second
vocabulary. **Names are `String` here for exactly that reason** (that is what
`global_registry` keys on), not atoms.

## 3. Where it lives: C runtime, not a March actor

The obvious cheap implementation is a registry *actor* holding a `Map`. Reject
it:

- every lookup becomes a message round-trip and a scheduling hop;
- it is a single-actor bottleneck on a path that wants to be as cheap as
  `send`;
- it cannot be consulted from inside the runtime's own send path;
- and it cannot be cleaned up automatically on death, because `do_actor_death`
  runs in the runtime and would have to *message* the registry to unregister —
  during teardown, into a mailbox that may be bounded or full.

So: a C table beside `g_actor_tbl` in `runtime/march_runtime.c`, following the
discipline Task 10 established for the actor table.

## 4. Data structure and concurrency

```c
typedef struct march_name_entry {
    char                     *name;        /* owned copy */
    void                     *actor;       /* actor record ptr, NULL = free slot */
    _Atomic(struct march_name_entry *) next;
} march_name_entry;

static _Atomic(march_name_entry *) g_name_tbl[MARCH_NAME_BUCKETS];  /* 256 */
static pthread_mutex_t g_name_mu = PTHREAD_MUTEX_INITIALIZER;
```

Discipline, mirroring `find_meta` (Task 10):

- **Writers** (`register`, `unregister`, death cleanup) take `g_name_mu`.
- **Readers** (`whereis`) take **no lock**: acquire-load the bucket head and
  walk. Safe because entries are **insert-only** — see below.
- Publication is a release-store of the bucket head after `next` is written.

### Unregistration without unlinking

Names must be *removable* (an actor dies, a name is reused), but unlinking
breaks the lock-free reader. Resolve it the same way the actor table does —
never unlink. An entry is **retired by clearing `actor` to NULL** (a release
store) rather than removing the node; `whereis` treats NULL as absent, and
`register` reuses a retired entry with a matching name instead of allocating.

This bounds table growth by *distinct names ever used*, not by registrations —
the natural shape, since names are a small fixed vocabulary in practice
("ledger", "gateway") re-registered across many incarnations. It also keeps
the reader honest without hazard pointers or epochs.

## 5. Semantics

**Uniqueness.** One actor per name (Elixir's `:unique`). A second `register`
for a live name fails rather than overwriting — silently stealing a name is
the kind of thing you debug at 3am. Duplicate/group registration is explicitly
out of scope: `stdlib/pubsub.march` already covers fan-out to many actors.

**One name per actor?** No — permit an actor to hold several names. Nothing in
the structure needs the restriction, and forbidding it costs a reverse index.
Death cleanup must therefore retire *all* of an actor's names (see §6).

**Automatic cleanup on death is mandatory, not optional.** Without it a name
resolves to a corpse and the whole point is lost.

**Registering a dead actor** fails. **`whereis` of a name whose actor has since
died** returns `None` — check liveness (`fields[3]`) at lookup, don't trust the
entry alone, since death cleanup and lookup race by nature.

## 6. Death cleanup

`do_actor_death` gains a call to retire the dying actor's names.

The cost to watch: with only a name→actor table, cleanup is an O(buckets ×
chain) scan for the dying actor. That is a full table walk **per actor death**,
and the churn scenario in `scripts/actor-load.sh` kills 40 000 actors — this
would reintroduce exactly the O(n)-per-death cost Task 15 removed from
supervisor lookups. So: keep a **reverse pointer on the actor's meta** — a
small list of the names it holds (`march_actor_meta` already carries per-actor
side data such as `monitor_head`, `cleanup_head`). Cleanup then touches only
this actor's own names.

Ordering inside `do_actor_death` matters. Retire names **before** the monitor
Down notifications fire: a watcher woken by a Down that immediately does
`whereis(name)` must not see the dead incarnation. (This ordering constraint
lands in the same function as the reason-carrying Down work — see
`specs/todos/2026-08-12-monitor-down-carries-no-reason.md`; do them together.)

## 7. Surviving a restart — the actual point

Two candidate mechanisms:

1. **The child re-registers itself** in its `init`. Rejected: `init` takes no
   parameters, so the name would have to be baked into the actor definition,
   which makes it a property of the *type* rather than of the instance — wrong
   for a pool of N workers.
2. **The supervisor re-registers the replacement.** `march_respawn_child`
   already runs on every restart and already knows the crashed child's
   `pid_index`. Have it read the names held by the crashed incarnation (via the
   reverse pointer from §6, captured before cleanup retires them) and register
   the new child under the same names.

Take (2). It needs **no syntax change** to `supervise` blocks: a child that was
registered stays registered across restarts because the supervisor carries the
name forward, and a child that was never registered is unaffected.

The sequencing must be deliberate, since §6 retires the names during
`do_actor_death` and the restart may be *delayed* by up to ~3.2s of backoff
(Task 16). During that window the name correctly resolves to `None` — the actor
genuinely does not exist yet. Callers must handle `None` from `whereis`; this
is the honest signal that the service is mid-restart, and is strictly better
than the current situation (a `Pid` that looks fine and silently drops).

## 8. Surface API

New builtins (each needs all four sites — typecheck / defun / llvm_builtins /
eval — per the `compiler-builtin` skill):

| Builtin | Type | Notes |
|---|---|---|
| `actor_register` | `String -> Pid(a) -> Bool` | false if name taken or actor dead |
| `actor_unregister` | `String -> Bool` | false if not registered |
| `actor_whereis` | `String -> Option(Pid(a))` | `a` fresh, as `spawn`'s Pid is |
| `actor_registered` | `Unit -> List(String)` | live names; feeds the introspection todo |

Stdlib wrapper, `stdlib/actor.march`:

```march
Actor.register(name, pid)   -- Bool
Actor.unregister(name)      -- Bool
Actor.whereis(name)         -- Option(Pid(a))
Actor.registered()          -- List(String)
```

`Actor.whereis` returning `Option` rather than a bare `Pid` is load-bearing —
it forces the caller to handle the mid-restart window from §7.

Deliberately **not** proposed: making `send` accept a name. Overloading `send`
would hide a fallible lookup inside an operation whose failure mode is already
subtle (`None` for a dead actor); an explicit `whereis` keeps the two failures
distinguishable. A `Actor.cast_named` / `call_named` convenience can follow
later if the explicit form proves noisy in practice.

## 9. Interpreter parity

The interpreter keeps its own registry (a `Hashtbl` beside `actor_registry`)
with the same semantics. Both backends must agree, pinned by a golden test —
this is exactly the class of divergence that bit compiled `mailbox_size`
(returning the monitor Down count instead of queue depth) before the 2026-08-12
hardening caught it.

## 10. Test plan

Beyond unit coverage of register/whereis/unregister:

- **The restart witness**, which is the whole feature: register a supervised
  child, kill it repeatedly, and reach it by name after every restart *from a
  holder that never sees the new Pid*. This must be a native golden, since the
  supervision plane is where interpreted and compiled have historically
  diverged.
- **Death cleanup**: `whereis` returns `None` after a kill with no restart.
- **Name reuse**: register → kill → register a *different* actor under the same
  name succeeds (proves retire-and-reuse, not permanent occupancy).
- **Churn cost**: extend `bench/actors/spawn_churn.march` with registrations to
  confirm death cleanup stays O(names held) and does not reintroduce a
  per-death table walk (§6).
- **Send path unaffected**: the fan-in scenario in `scripts/actor-load.sh` must
  not regress — the registry must not put a lock anywhere `send` touches.

## 11. Open questions

1. **Should `whereis` check liveness, or is the retire-on-death race tight
   enough?** Proposed: check. It is one load of `fields[3]` on a path that is
   not per-message hot.
2. **Case sensitivity / name validation** — presumably raw `String`, no
   validation, matching `global_registry`.
3. **Should the supervisor re-register names for a child it did not itself
   register?** §7 says yes (it carries forward whatever the incarnation held).
   The alternative — only names the supervisor knows about — needs a child-spec
   field and is worth revisiting if child specs grow anyway for restart types
   (`specs/todos/2026-08-12-supervisor-restart-types-and-child-specs.md`).
4. **Distributed seam**: when a name is registered locally, should it
   automatically be announced to `global_registry`? Proposed: no, not
   implicitly — keep local and global explicit, and design the bridge when the
   distributed-plane work (`specs/todos/2026-08-11-actor-hardening-distributed-plane.md`)
   is picked up.
