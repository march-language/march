# A caught panic whose authority mark is a refcounted cell is now tested (2026-11-24)

Was `[P1]` `specs/todos/2026-11-19-ocap-mortal-mark-catch-fixture.md`. No runtime
change: the fixture found no use-after-free. `march_cap_unwind` over-counts (a
leak, see below), it does not under-count.

## What was added

`test/cap_conformance/panic_caught_mortal_mark.march`, run on every engine by
`test/run_cap_conformance.ml` (interpreter, JIT, compiled, JS, REPL):

- scoped `f` calls scoped `g` with a different `needs`, so `g`'s frame is pushed
  on a non-empty slot and is an allocated, refcounted cell (a frame pushed from
  the launch authority is cached and immortal, which is why
  `panic_caught_restores_authority` could not see a wrong count);
- `g` catches, by `__try_call_val` and by `try_finally`, a panic raised in
  scoped `h`, and one raised two frames deeper in scoped `k`; three times each;
- `g_outside` catches function values made in `main`. This is the part that can
  fail. A closure made inside `g` holds a reference to `g`'s frame, and a panic
  abandons it, so every such catch leaves a spare reference that hides a count
  one or two too low. The values from `main` hold none.

`specs/lang/golden/sanitize.sh` has a new `cap` leg (CI job `sanitize-gate`,
shard 1) that builds this fixture and two other caught-panic fixtures under
AddressSanitizer. `run_cap_conformance` does not build with a sanitizer.

## Proof the fixture can fail

With `march_cap_unwind`'s `march_incrc(mark)` replaced by
`march_cap_release(mark)` in a copy of the runtime (`MARCH_RUNTIME_DIR`):

- before `g_outside` was added: plain and ASan builds both passed, output
  identical (the spare references absorbed it);
- with `g_outside`: the plain build prints different output, the ASan build
  aborts with `heap-use-after-free ... in v_is_cons`.

The unmodified runtime is clean under ASan (macOS arm64, 2026-11-24).

## What the reference-count trace shows today

`march --rc-trace --compile`, `MARCH_TRACE_GC=1`, `scripts/gc-trace-report.py`:
15 authority cells (allocated at `Authority.enter_fn#3:march_cap_push`) are live
at exit. The todo asked for none; that is the next item,
`specs/todos/2026-11-19-ocap-cap-unwind-mark-leak.md`, which now carries the
breakdown.
