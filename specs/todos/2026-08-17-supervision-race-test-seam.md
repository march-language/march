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
