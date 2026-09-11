# The supervisor restart-race class now has a deterministic test venue

Landed 2026-09-10, option 2 of the todo below (the injected stall). Option 1
(an exported C hook around `march_supervisor_notify`) was not built: the
strategy functions respawn children through generated `_spawn` code, so a
C-level call with synthetic records could only ever reach the marker
bookkeeping, not the interleaving the races live in.

## The seam

`MARCH_SUP_TEST_STALL_MS=<ms>`, read once and cached, makes a synchronous
batch restart loiter between the leaf-lock release (where the in-flight marker
was just claimed) and the strategy call. The stall **yields**
(`march_sched_yield` in a loop until the deadline; `usleep` only outside a
green thread) rather than sleeping: a blocking `usleep` pins the OS worker, and
a sibling whose crash is queued on that worker's run queue then runs only
*after* the stall — the first version did exactly that and deflected the
sibling in roughly half of runs, which is the flaky shape the todo forbids.
Yielding gave 40 of 40 deflections under both one and the default number of
schedulers. Only the `claimed_sync_batch` path stalls; the delayed path already
has its backoff window and non-batch strategies have no marker to race.
Unset, it costs one cached `getenv`.

Documented next to `MARCH_SUP_TRACE` in `docs/supervision.md` and
`specs/lang/supervision.md`.

## The test

`test/native/supervisor_deflected_crash_absorbed.march`, compiled-only, run
under the stall and `MARCH_SUP_TRACE=1` with stderr captured into the golden.
A `rest_for_one` supervisor with children `lo` (index 0) and `hi` (index 1);
main kills `hi` and a `Killer` actor — on a scheduler worker, so a different
OS thread — kills `lo` inside the window. `lo`'s crash is deflected (the
` (batch restart already pending, skipped)` trace line is in the golden: a
run where the deflection did not happen fails instead of passing vacuously).
The first pass covers only `[1, n)`, so `lo` is restarted only by the absorb
loop's second pass.

Red control: with the absorb loop disabled (`if (!claimed_sync_batch) return;`
made unconditional), 5 of 5 runs print `lo restarted: false` / `lo alive:
false` — the permanently-dead-child bug commit `a31ca9fb` fixed, reproduced
by construction.

## A trap hit on the way

The first stall runs "did nothing": the compiled fixture links the runtime
copy staged under `_build/default/runtime`, which a targeted
`dune build bin/main.exe` does not refresh. Build any rule that depends on
`runtime/*.c` first (CLAUDE.md, "Build & test").

## Original todo

`[P2]` # No deterministic test venue for the supervisor restart-race class

## The gap

Task 3 of the 2026-08-16 actor race-fix plan (commit `a31ca9fb`) fixed a
sibling-crash race in synchronous batch restarts by claiming a
`batch_restart_in_flight` marker across the whole strategy call, plus an
absorb loop keyed on `pending_drop_count`. That fix shipped with **no**
executable regression test, by explicit 2026-08-16 human ruling: the race
cannot be forced deterministically across two OS threads, so a fixture would
pass identically before and after the fix (a test that cannot fail against
broken code is not evidence). Task 3's reviewer went further and confirmed
there is currently **no venue at all** — deterministic or not — for testing
this bug class:

- `test/dune:771-773` links `test_supervision` against
  `march_lexer march_parser march_ast march_desugar march_eval alcotest unix`
  only. `march_eval` is the tree-walking interpreter; it has no C runtime, so
  it structurally cannot reach `march_supervisor_notify` or any of the
  restart-marker machinery, which lives entirely in the C runtime.
- `march_supervisor_notify` is declared `static` at
  `runtime/march_runtime.c:3489`, so it is not externally linkable even if a
  C test target wanted to call it directly.
- `test/dune:398-435` (the `test_actor_registry_runner` rule) shows the
  pattern the project already uses to reach runtime internals from C: it
  compiles a small `.c` test file against `../runtime/march_runtime.c` and
  friends as separate translation units, run via `%{cc}` — but no such target
  exists for the supervisor-restart path today, and a plain separate-TU link
  still can't call a `static` function from outside its own file.

(All three references verified against source on this branch, 2026-08-17,
ahead of filing this todo.)

## Why it matters

Tasks 2, 3, and 4 of the same plan hardened three distinct supervisor/actor
races on structural argument alone, because none of them could be reproduced
as a red-green test with the tools available today. That is a defensible
one-off call, but it means the entire supervisor-restart-race class is now
permanently unverifiable by regression test unless a seam is built
deliberately. The next bug in this area — or a future refactor that
reintroduces one of these three races — will have the same "no venue" problem
and the same debate about whether structural argument is enough.

## Sketch

Two independent options, either sufficient on its own:

1. **Test-only exported hook.** Add a `MARCH_TEST_BUILD`-gated (or always-on,
   `march_test_` prefixed) non-static wrapper around
   `march_supervisor_notify` — or around the specific claim/release pair
   added in Task 3 — so a C test target (built the same way
   `test_actor_registry_runner` is: separate-TU compile of the test file
   against the runtime `.c` sources) can call directly into the restart path
   with synthetic actor/supervisor records, bypassing the scheduler entirely
   the way `test_actor_registry.c` already does for the registry.

2. **Injected stall for real concurrency.** An environment-gated delay (e.g.
   `MARCH_SUP_TEST_STALL_MS`, read once and cached) inserted between the
   leaf-lock unlock and the strategy call inside `march_supervisor_notify`.
   A test can then spawn two real OS-thread crashes timed to land inside that
   window, turning "cannot be forced deterministically" into "reliably forced
   by construction" — this is the more valuable of the two because it
   exercises the actual two-thread interleaving the races live in, not just
   the sequential logic after the fact.

Either requires a new `test/dune` stanza (mirroring the
`test_actor_registry_runner` pattern for option 1, or a new alcotest/native
harness for option 2) since `test_supervision` cannot be extended in place —
it does not link the runtime at all.

## Where this came from

Filed per the 2026-08-16 actor race-fix plan's Task 6 close-out
instructions, which required recording this gap as a todo rather than
re-deriving it. Original finding: Task 3's reviewer
(`.superpowers/sdd/2026-08-16-actor-race-fixes-and-links-removal/progress.md`,
"Task 3: FINDING (infrastructure, out of scope)").
