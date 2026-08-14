# Named process registry: hold names across a restart, not stale Pids — DONE

**Filed:** 2026-08-12 (as `specs/todos/2026-08-12-actor-named-registry.md`)
**Landed:** 2026-08-14, branch `claude/named-registry-impl-4d7e`
**Design spec:** [`specs/2026-08-12-named-registry-design.md`](../2026-08-12-named-registry-design.md)
**Plan:** `docs/superpowers/plans/2026-08-12-named-registry.md` (9 tasks)
**Per-task implementation detail:** `.superpowers/sdd/2026-08-12-named-registry/task-*-report.md`
(gitignored — the load-bearing findings are reproduced here and in the todos
this entry files, so nothing depends on that directory surviving).

## The gap this closed

Supervision self-heals, but a restarted child gets a **new** Pid. The supervisor
rewrites its own state, so the *inside* of the tree recovers; every holder
**outside** it is left pointing at a dead incarnation. `get_cap`'s epoch counter
*detects* the staleness but offers no way to re-resolve. The fix every
comparable runtime reaches for: hold a name, resolve it at use time.

## What shipped

| Commit | What |
|---|---|
| `acf9a35b` | Vault concurrent reads (striped reader-count lock) — the substrate |
| `3c4e566a` | Vault reads need no capability; naming ops and writes keep `IO.Mut` |
| `49f713ed` | Runtime registry: forward table, reverse index, four C entry points |
| `4c7d7b45` | Registry stale-overwrite/retire race fix, `g_registry_mu` |
| `93dda25c` | `Actor.register` / `whereis` / `unregister` / `registered` — builtins + stdlib |
| `15790cd3` | Names retired on actor death, before any monitor `Down` fires |
| `f53f60b8`, `e5a64520`, `d488c08a` | Names survive a supervisor restart (incl. batch strategies) |
| `c4889377` | Spawn-churn benchmark exercises registration + retire |
| `1496723a` | Docs — `## Named Actors` in `specs/lang/actors.md` and `docs/actors.md` |
| `a9032530` | **Actor-refcount dispatch UAF** — see "The bug this uncovered" |

### Surface

`Actor.register(pid, name) -> Bool`, `Actor.unregister(name) -> Bool`,
`Actor.whereis(name) -> Option(Pid(a))`, `Actor.registered() -> List(String)`
(order unspecified). `whereis` and `registered` require **no capability**: the
runtime owns the well-known table, so no March-level naming op happens.
`register`/`unregister` likewise carry none — the ambient-authority argument in
design §7 applies to `vault_new`/`vault_whereis`, which the registry never calls
from March.

Semantics as designed: one actor per name (a second `register` for a *live*
name fails rather than stealing); several names per actor; registering a dead
actor fails; `whereis` re-checks `fields[3]` liveness at lookup, so a dead
incarnation resolves to `None` even before cleanup runs.

### Storage

Forward table: a Vault table the runtime creates lazily under the well-known
name `"$actor_registry"` (`MARCH_REGISTRY_TABLE_NAME`, `runtime/march_runtime.c`).
Reverse index: `char **reg_names` / `int reg_name_count` **on `march_actor_meta`** —
see "Deviations" below. `g_registry_mu` serialises every mutation of a
`reg_names` array; it is a strict leaf lock (nothing called under it can park a
green thread).

## The restart witness

`test/native/actor_registry_restart.march` / `.expected` — the golden the whole
feature exists for. A supervised `Fragile` child is registered under `"fragile"`,
crashed via `panic()` inside a handler (the real `setjmp`/`longjmp` crash-trap
path, not `kill()`), and then resolved **by name** from a `main`-level holder
that never saw the replacement's Pid. Two crash/restart cycles, to prove the
name-stash is re-established on every restart rather than consumed once:

```
registered: true
respawned with new pid: true
reached by name after restart
respawned again with new pid: true
reached by name after second restart
```

Non-vacuous, verified by file-swap against the pre-fix runtime (never
`git stash` — shared stash stack across worktrees): the same program on the
runtime immediately before `f53f60b8` prints `lost after restart` /
`lost after second restart`.

`test/native/actor_registry_restart_batch.march` is the sibling witness for
`one_for_all`: two named children, only one crashed, **both** names reachable
afterwards. Its own pre-fix control prints `child-a: lost after restart` —
the untouched sibling's names were captured never, because
`march_one_for_all_restart` / `march_rest_for_one_restart` null out
`cm->supervisor` before calling `do_actor_death`, which was the capture gate.
Capture now happens at those batch call sites explicitly.

Death cleanup is pinned separately by `actor_registry_retire.march` and
`actor_registry_retire_vault.march` — the latter reads the raw
`"$actor_registry"` Vault table rather than the liveness-filtered
`Actor.*` accessors, because both of the obvious assertions (`whereis` returns
`None`; the name is re-registerable) print identically with
`registry_retire_actor` deleted outright. C-level coverage:
`test/test_actor_registry.c`.

## Harness numbers

`bench/actors/spawn_churn.march` now registers each churned actor under a
per-iteration name before killing it, so all 40 000 deaths exercise
`registry_retire_actor`. All measurements same-box, interleaved A/B by file-copy
swap, on a box under load average 13–17 from other sessions — absolute wall
times are inflated, so read the medians and the A-vs-B relation, not the
milliseconds.

| scenario | pre-edit median | post-edit median |
|---|---|---|
| `fanin` (send path) | 249 ms | 240 ms |
| `churn` (40 000 spawn→register→send→kill) | 902 ms | 966 ms |

- **No send-path regression.** The `fanin` medians are within noise of each
  other, and B is if anything marginally faster — consistent with the registry
  putting no lock anywhere `send` runs. This was design §11's explicit
  requirement.
- **Cleanup is O(names held), not a table walk per death.** 40 000
  register+retire pairs add roughly 60–70 ms to a ~900 ms scenario (~1.6 µs per
  pair) against a 120 000 ms gate. A per-death table walk would be quadratic and
  would blow that gate by orders of magnitude. **No gate was raised or loosened,
  and `churn` was not added to `EXPECTED_FAIL`.**

Vault lock measurements that justified the substrate choice are in the
"Deviations" section below.

## The bug this uncovered — bigger than this plan

Registering churned actors made `spawn_churn` fail ~20% of runs with
`march: RC underflow (rc was -6899412650951359789)`, `SIGBUS`, or `SIGTRAP`.
It was **not** a registry race. `actor_green_thread` was clobbering the actor
record's refcount word (`a[0] = 1`) around every message dispatch, publishing a
false refcount to every other thread; a concurrent `march_decrc` could observe
`prev == 1` and free a record with live owners. The defect predates this plan
entirely and reaches any multi-scheduler program where an actor has a second
owner while it handles a message — a monitor, a Pid stored in a Vault, a Pid
passed to another actor. `Actor.register` merely made it *reachable*, because
`march_vault_set` incrc's the stored actor and so raises a churned actor's true
refcount above 1.

Fixed in `a9032530` by deleting both stores (the clobber was dead code — 
`llvm_emit.ml`'s `EReuse` arm already mutates actor structs in place
unconditionally). Full write-up, including the direct instrumentation that
caught a premature free of a record whose true refcount was 4, in
[`specs/progress/2026-08-14-actor-dispatch-rc-clobber-uaf.md`](2026-08-14-actor-dispatch-rc-clobber-uaf.md).
Evidence: pre-fix **6/30** crash rate, post-fix **0/60**; the decisive control
was "register but no `send`" — every bit of registry work, no dispatch window —
which is clean **0/30**, and which no registry-locking theory predicts.

## Deviations from the design spec, with reasons

### 1. The reverse index lives on `march_actor_meta`, not a second Vault table

Design §3 called for two Vault tables, `name → pid` and `pid → names`, mirroring
Elixir's two ETS tables. Shipped: the forward table is a Vault table as
designed; the reverse index is two plain fields on `march_actor_meta`
(`char **reg_names`, `int reg_name_count`).

Reason: the meta already exists per actor, is address-stable, and is **never
freed or unlinked** (`g_actor_tbl`'s documented invariant), so cleanup in
`do_actor_death` is a direct field read with no table lookup, no key
construction, and no second lock to order against the first. Elixir needs a
second ETS table because a BEAM library has no place to hang per-process state;
we own the runtime and do. This is strictly cheaper on the death path, which is
the only path that reads the reverse index. The cost: the reverse index is not
introspectable from March the way the forward table is (which
`actor_registry_retire_vault.march` exploits) — acceptable, since the forward
table is the one users would want to inspect.

### 2. Concurrent reads shipped as a striped reader-count lock — not lock-free, and deliberately not `pthread_rwlock_t`

Design §5 wanted an "ETS `read_concurrency` equivalent", and the Vault todo
sketched a lock-free/epoch-reclamation scheme. Neither shipped. What shipped is
a hand-rolled striped reader-count lock (`vault_rwlock_t`, `VAULT_RD_STRIPES = 16`,
one cache-line-aligned `_Atomic int64_t` counter per stripe, writer-preference
flag, writers serialised by a plain mutex) in `runtime/march_extras.c`.

`pthread_rwlock_t` — the literal first choice — was **built first and rejected on
measurement**, not on taste. Same box, same test (4 threads, 1M reads each,
median-of-5, ratio of four-thread wall time to solo):

| lock | ratio |
|---|---|
| original exclusive `pthread_mutex_t` | ~9.5x |
| `pthread_rwlock_t` | **~18x** — worse than the mutex it replaced |
| striped reader-count lock, same key | 5.7–6.5x |
| striped reader-count lock, distinct keys | median ~2.0x |

The rwlock pathology reproduced in a synthetic benchmark with no Vault code at
all, and is a documented Darwin trait (Apple's `pthread_rwlock` carries
fairness bookkeeping that serialises readers harder than a plain mutex under
contention; WebKit ships its own `ReadWriteLock` for the same reason). CI runs
`macos-15`, so shipping the spec's literal choice would have regressed Vault
reads on every macOS leg — the opposite of the task's goal.

The same-key/distinct-key split is the other half of the finding: **same-key
reads are bounded by refcount contention on the single shared value, not by the
table lock.** `march_vault_get` does `march_incrc(n->value)` inside the read
section, so N threads reading one key do N atomic RMWs on one 8-byte word
regardless of how good the lock is. Isolated two ways: a distinct-key variant of
the identical code clears 3x, and a diagnostic build with the `incrc` removed
(never committed) drops the same-key ratio to ~1.5–2.0x. ETS sidesteps this by
not refcounting reads at all. This is why the actors docs say **resolve a name
once and cache the Pid, re-resolving on `None`**, rather than resolving per send.

Test split follows from that: `test/test_vault_concurrency.c` (same key, bound
`*9`, "never worse than where we started") stays in `runtest`;
`test/test_vault_distinct_keys_scale.c` (distinct keys, bound `*3`) is a
parallel-scaling *benchmark*, so it lives on its own `@vault-scale` alias and
runs in CI on dedicated runners rather than flaking on shared dev boxes.
`test/test_vault_hammer.c` covers the one path neither times: the writer's drain
against concurrent readers.

A memory-ordering bug found in review of that lock was fixed in the same round:
the reader's increment/re-check and the writer's flag-store/drain form a Dekker
store-buffering pair, and all **four** operations now use `seq_cst` — matching
this repo's own precedent in `runtime/march_runtime.c`'s
`task_wait_done`/`march_thunk_trampoline` ("SEQ_CST ON THE NEXT TWO OPERATIONS
IS THE WHOLE FIX"), which was the same bug class in production.

### 3. `Actor.register` takes `(pid, name)`, not `(name, pid)`

Design §10's table wrote `actor_register : String -> Pid(a) -> Bool`. Shipped
pid-first, matching `monitor`/`kill`, which is what a March caller expects.
`llvm_emit.ml` carries a dedicated `EApp` arm that swaps the two atoms back for
the C ABI (`march_actor_register(name, actor)`).

### 4. Open question §12.1 answered "yes"

`whereis` checks liveness. Cleanup and lookup race by nature, and the check is
one field load on a path that is not per-message hot.

## Known gaps left open (each has its own `specs/todos/` entry)

- **Interpreter parity: names do NOT survive a supervisor restart interpreted.**
  Compiled-only today. `specs/todos/2026-08-14-interpreter-registry-restart-parity.md`
- **No deterministic regression test pins the dispatch-window UAF.**
  `specs/todos/2026-08-14-deterministic-premature-free-reproducer.md`
- **Heap corruption when an actor holding 2+ registry names dies via `panic()`.**
  Pre-existing crash-trap/`longjmp` bug, not registry logic.
  `specs/todos/2026-08-14-crash-trap-longjmp-heap-corruption.md`
- **Vault write partitioning and typed handles** remain open —
  `specs/todos/2026-08-12-vault-toward-ets-semantics.md` items 2 and 3.
- **Distributed seam** (design §12.5): a local registration does not announce
  into `stdlib/global_registry.march`, deliberately. Design the bridge when
  `specs/todos/2026-08-11-actor-hardening-distributed-plane.md` is picked up.
- **`docs/overload-resilience.md`** was written on the sibling branch
  `claude/actor-system-hardening-6bd64a` and does not exist here. Once the two
  branches meet, add one sentence next to the `mailbox_size(pid)` polling
  guidance: a monitoring loop gets a named actor's Pid from `Actor.whereis`,
  resolved once and re-resolved on `None`.

Explicitly **not** a gap: the JIT/REPL does not carry the registry across
incremental compiles, but this is not user-visible. `lib/repl/repl.ml:311-315`
disables every JIT path as soon as a `DActor` declaration is seen, so a REPL
actor program runs on the interpreter's `named_registry` Hashtbl, which *does*
persist across incremental entries (it is cleared only by
`reset_scheduler_state` / `eval_module_env`, neither of which the per-decl path
runs). Verified interactively. No todo filed; recorded here so it is not
re-derived as a bug.

## Acceptance — met

> A supervised child registered under a name, killed repeatedly, is reachable by
> that name after every restart — from a holder that never saw the new Pid.

Pinned by `test/native/actor_registry_restart.march` (two cycles, `one_for_one`,
crash via `panic()`) and `actor_registry_restart_batch.march` (`one_for_all`,
uncrashed sibling included), both native goldens — supervision is where the two
backends have historically diverged, and per the gap above they still do for
restart carry-forward.
