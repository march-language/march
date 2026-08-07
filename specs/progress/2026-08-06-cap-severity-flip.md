# The severity flip: an undeclared direct builtin call is an error

Landed 2026-08-06. Closes the warning-vs-error gap that
`specs/2026-08-06-per-function-capability-closure-design.md` was written to
unblock.

## What changed

`Check 1b` — a body-scanned builtin call implying an undeclared capability —
moves from `Err.warning_with_fix` to `Err.error_with_fix` (a new emitter; the
fix payload has to survive the promotion, or `forge fix` and the LSP quick-fix
would stop offering the one-line remedy exactly when it became mandatory).

Two adjacent checks were deliberately **not** flipped:

- **Check 1c** (an `extern` block implying `IO.Foreign`) stays a warning.
- The **declared-but-unused** warning stays a warning. Only the undeclared-USE
  direction escalated.

## Why it was blocked, and why it is not any more

`needs` was a hard floor for capability-*passing* code and merely advisory for
a direct builtin call — which is the code most likely to abuse it. The blocker
was **granularity, not severity**: capability propagation worked at module
granularity, so contracting `List` (whose `pmap` calls `task_spawn`) with
`needs IO.Spawn` would have forced that on every module importing `List` just
to call `map`. Every program lands at `needs IO` and the precision evaporates.
Per-function transitive closure fixed the granularity; this change follows it.

## What it guarantees — and the part that is easy to over-read

Measured 2026-08-06:

| route | `--check` | `--compile` (default) | `--compile --cap-strict` |
|---|---|---|---|
| direct builtin `file_read` | **error** | error | error |
| stdlib-mediated `File.read` | silent | silent | **CAPABILITY CEILING** error |

So the flip catches a **direct** call and not the same operation routed through
a stdlib wrapper. The complete check remains `--cap-strict`, which works on
emitted code and cannot be evaded by re-routing through a helper.

This does **not** weaken any security property — the sandboxing claim never
rested on the body scan. What it does is make a *partial* channel look total,
which is a documentation hazard, so `docs/capabilities.md` and
`specs/lang/capabilities.md` now state the limitation explicitly instead of
implying a guarantee.

Two things unchanged and worth restating, because "capabilities are now
enforced" invites the wrong reading: `needs` is a self-declaration (any module
may write any `needs` line), and IO builtins take no capability argument. This
makes you *declare* what you touch; it does not make anyone *grant* it.

The genuinely load-bearing gap is upstream of all this and untouched:
`--cap-strict` is opt-in and compile-only, so the default build enforces
nothing on the mediated route.

## The stdlib is deliberately not migrated

This is the one non-obvious decision in the change.

An early pass autofixed `needs` into 20 stdlib files. That broke a
`cap_ceiling` test whose own comment had predicted it: *"dropping the prelude's
declarations from the OWN set must not stop a real console use from being
seen."*

`Prelude.println` wraps the raw `print` builtin, and **every** user `println`
routes through it. Declaring `needs IO.Console` on `Prelude` satisfies the
console use *there*, so `--cap-strict` stops attributing a user's own `println`
to the user's module — silently weakening the exact check it exists for.

The stdlib does not need the declarations anyway: `check_module_needs` already
filters capability uses whose span is a stdlib file (`span_is_stdlib`), so a
user program builds fine against an undeclared stdlib. All 20 files were
reverted.

One consequence: `assert_stdlib_file_typechecks_cleanly`, which typechecks a
stdlib file **standalone** to surface internal type errors the CLI's user-file
diagnostic filter hides, now registers the file in `stdlib_source_files` first
— exactly as `bin/main.ml` does. Without that the flip fires on the stdlib's
own builtin calls. The test's purpose is unaffected; internal type errors still
surface.

## Migration

| | |
|---|---|
| user-facing `.march` (bench, examples, test/native) | 191 files, 198 inserts |
| conformance corpus | 123 inserts |
| OCaml test fixtures | ~160 inserts across 8 files |
| stdlib | **0 — deliberately** |

Driven by the compiler's own autofix (`--check-json` emits
`{"kind":"insert","after_line":N,"text":"  needs IO.Console"}`, the same
payload `forge fix` consumes), applied to a fixpoint since one declaration can
reveal another. Verified the resulting diff contains `needs` lines only, with
no duplicates.

## What cost the most time, and what a reviewer should look for

**An automated fixer will "fix" the tests that exist to be broken.** A blanket
pass added `needs` to fixtures whose entire premise is *omitting* it, and each
one then passed while testing nothing:

- `cap_body_enforce` — the group that tests this very check
- `cap_infer` — chain-hint tests, which need the capability MISSING to emit a hint
- `cap_ceiling` — `test_direct_builtin_route`, and `Dep` in the
  dependency-exceeds-its-ceiling test
- `test_netlisten_not_satisfied_by_netconnect` — got `needs IO.NetListen`,
  destroying the premise that NetListen is unsatisfied
- `test_cap_body_let_body` — the DLet case

Fixed by adding a negative-fixture guard (skip literals whose enclosing
function name matches `missing|without|undeclared|no_needs|warn|unused|...`)
and restoring the damaged functions from HEAD. **The guard over-skips too** —
it missed `typecheck.152` (a test named for an offer-label *warning*, nothing
to do with `needs`) and `PartialApp` (bound to `attrib_unused_feature_src`).

**Review the diff with that specifically in mind.** An inserted `needs` line in
a test that asserts a capability is *missing* is invisible unless you look for
it.

Two smaller classes, both worth knowing:

- **Position-asserting tests break on line shifts.** `typecheck.084`/`086`
  assert a diagnostic's `start_line`; inserting one `needs` line moved the body
  down by one.
- **A section-wide warning→error conversion over-reaches.** It caught the
  extern `IO.Foreign` assertions (Check 1c was not flipped) and the
  `"unused capability"` assertion (a different warning). Both reverted.

And a subtle one: after the flip, `has_warning_with ctx "..." = false`
assertions on the body-scan diagnostic pass **vacuously** — there is no warning
because it is now an error. Those had to be converted too, not just the failing
ones, or they would have silently stopped testing anything.

## Test alignment

The `cap_ceiling` group needed a semantic decision rather than a patch. With
the flip, a direct builtin call is rejected at typecheck, so compilation stops
**before** `--cap-strict`'s ceiling pass runs and those tests could no longer
reach their assertion.

They were re-pointed to a new `rejects_at_typecheck` helper rather than
deleted: they still assert the program is rejected — the property that matters
— and now record *where*. Deleting them would have removed the only regression
guard on routes that used to be the ceiling's job. The ceiling keeps its own
witness in `test_stdlib_route_was_completely_silent`, the stdlib-mediated route
typecheck cannot see, which still passes through the original `rejects` helper
unchanged. That asymmetry is the point.

`cap_body_enforce` had 30 assertions converted warning→error, including
`test_cap_body_warn_not_error`, which existed to pin that the body scan did
*not* escalate. It is inverted and kept rather than deleted, so the flip is
visible in the diff.

## Verification

compiler **797**, eval **256**, stdlib **833**, codegen **546**, types corpus
**269/269**, `check-docs.sh` pass — all under the flip.
