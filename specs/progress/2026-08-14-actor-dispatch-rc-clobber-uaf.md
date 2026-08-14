# Actor dispatch window clobbered the actor's refcount — use-after-free

**Status:** fixed. `runtime/march_runtime.c`, `actor_green_thread`.

## Symptom

`bench/actors/spawn_churn.march` (40 000 spawn→register→send→kill iterations)
died on ~20% of runs with `march: RC underflow (rc was
-6899412650951359789) — aborting` (SIGABRT), or bare SIGTRAP/SIGBUS with no
output. A garbage refcount, not a small negative one — i.e. freed-and-reused
memory being read as a header.

The scenario only started failing when it was changed to register each churned
actor under a per-iteration name before killing it (commit `c4889377`).

## Root cause

`actor_green_thread`'s receive loop bracketed every user message dispatch with

```c
int64_t saved_rc = a[0];
a[0] = 1;              /* FBIP: force RC=1 for in-place reuse */
...dispatch...
a[0] = saved_rc;
```

`a[0]` is the actor record's refcount — the same word every other thread
mutates atomically via `march_incrc` / `march_decrc`. The two plain stores are
neither atomic with those nor honest: for the whole duration of a handler, every
other thread saw the actor's refcount as `1`.

Two consequences, one merely lossy and one fatal:

- a concurrent `march_incrc` is silently discarded by the blind
  `a[0] = saved_rc` restore;
- a concurrent `march_decrc` observes `prev == 1` and **frees the record**,
  even though other owners still hold references.

`Actor.register` is what made this reachable: `march_vault_set` incrc's the
stored value, so a registered actor's true refcount is > 1 by construction.
Main's drop of `pid` at the end of a churn iteration then freed a record the
registry still pointed at; the subsequent `registry_retire_actor` →
`march_vault_get` / `march_vault_drop` → `march_decrc` read a refcount out of
the reallocated block.

### Observed, not inferred

Temporary instrumentation (a window-membership table checked on `march_decrc`'s
free path) caught it directly:

```
DIAG: window opened with true rc=4 actor=0x889445890 thread=0x16b80b000
DIAG: concurrent RC delta during dispatch window: a[0]=0 saved=4 actor=0x889445890
DIAG: PREMATURE FREE of actor 0x889445890 while its green thread is
      mid-dispatch; freeing thread=0x1f8db9d80
```

A different thread frees a record whose true refcount is 4. Every failing run
contained exactly one such event; clean runs contained none. Note the premature
free is *not* always fatal — 2 premature frees were observed across 15 runs
while only 1 run crashed, so the crash rate understates the corruption rate.

## Why the clobber was unnecessary

It was dead code kept alive by inertia. `lib/tir/llvm_emit.ml`'s `EReuse` arm
already special-cases actor structs (`Repr.is_actor_struct_type`, gated
structurally on field 0 being literally `$d_dispatch`, which no user identifier
can spell) and **always** mutates the actor in place — no RC load, no branch,
no fresh allocation. That code's own comment already noted that
`actor_green_thread`'s force "is itself racy against that concurrent incrc and
cannot be made safe." Nothing in an emitted handler reads `a[0]` at all.

## Fix

Delete both stores. The replacement is a comment recording why the window must
never come back: there is no safe version of it, because it necessarily
publishes a false refcount to a word other threads are concurrently RMW'ing. If
a future actor lowering reintroduces an RC-conditional reuse of the actor
record, the fix belongs in `llvm_emit` (keep the unconditional in-place store),
not here.

## Evidence

Same box, same loop, back-to-back, load average ~14–17 throughout. Pre-fix
binary built by restoring `git show HEAD:runtime/march_runtime.c` via file copy
(never `git stash` — shared stash stack across worktrees).

| build | failures |
|---|---|
| pre-fix | **6 / 30** |
| post-fix | **0 / 30**, then **0 / 30** again (0/60 total) |

Every build whose result is quoted here was made with `DUNE_CACHE=disabled dune
build --root . --force @bin/warm-cache` (the `@bin/warm-cache` alias is what
restages `_build/default/runtime` — `dune build bin/main.exe` alone does not),
with `.march/cas/artifacts-v2/` cleared before each compile, and with
`diff -q runtime/march_runtime.c _build/default/runtime/march_runtime.c`
asserted before each measurement.

Controls that localised the bug before the fix (30 runs each):

| variant | failures |
|---|---|
| churn without `Actor.register` | 0 / 30 |
| churn with `Actor.register` | 6 / 30 |
| churn with `Actor.register` but **no `send`** (no dispatch window opens) | 0 / 30 |
| churn with `Actor.register`, `MARCH_NUM_SCHEDULERS=1` | 0 / 20 (earlier run) |

The no-send control is the sharp one: it keeps the registry work and removes
only the message dispatch, and it is clean — which places the bug in the
dispatch window rather than anywhere in the registry's locking.

## Regression coverage

Five alcotest suites green (833 compiler / 256 eval / 575 codegen / 811 stdlib /
58 stdlib_march). All five actor-registry native goldens
(`actor_registry_{basic,retire,retire_vault,restart,restart_batch}`), all four
supervision goldens (`supervisor_{spawn_children,one_for_one_restart,
one_for_all_restart,rest_for_one_restart}`), and the C-level
`test_actor_registry_runner` pass, rebuilt `--force` with the cache disabled.

## Out of scope

The `setjmp`/`longjmp` crash-trap heap corruption when an actor holds 2+
registry names and dies via `panic()` is a separate, pre-existing bug in
`actor_green_thread`'s crash trap and is tracked elsewhere. It was not hit
during this work — every failure reproduced here was the churn UAF, which dies
during the churn loop, not in a crash-trap restart.
