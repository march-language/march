# A record type declared in one `check_module` changes a later, unrelated check's diagnostics

**Filed:** 2026-09-09
**Priority:** P2 — test-suite correctness hazard; no known effect on a single
compilation, which is all the CLI ever does

## Symptom

Two `March_typecheck.Typecheck.check_module` calls in one process are not
independent. A module that declares the structural record `{ a : Int }` changes
the diagnostic a LATER module gets for an unrelated same-short-name type
collision: the error still fires, but the explanatory note ("Two distinct types
are both named `Thing` …") is gone.

Found while adding capability-forge tests for `from_json` dispatch
(`specs/progress/2026-09-09-from-json-return-type-dispatch.md`). A new test in
`test/test_cap_unforgeable.ml` declaring

```march
type A = { a : Int }
```

made `test_compiler.ml`'s `same-name type collision: a note explains two
distinct types share the name` (error_improvements #22) fail — a test in a
different file, asserting nothing about records, that passes when run alone and
passes today with the offending declaration renamed.

## What is and is not implicated

Measured, not assumed:

- Unregistering the new tests and leaving the `from_json` dispatch change in
  place: run_compiler green. So the compiler change is not the cause.
- Keeping the new test and compiling the dispatch recording OUT
  (`if false && jname <> "to_json"`): run_compiler still FAILS. So the leak is
  pre-existing and independent of that work.
- Renaming the type and its FIELD (`FjdAlpha` / `fjd_alpha`): green. The field
  name matters, which is what points at a structural-record key rather than a
  type-name one.

## Where to start

A process-global keyed by record SHAPE rather than by check. `env.records` is
per-env and `type_map` is per-check, so neither is it; look for a module-level
`Hashtbl`/`ref` on the path that decides whether a same-short-name collision
gets its explanatory note. The interpreter has a documented global of this
family (`is_colliding_type_name`, `colliding_ctor_type_by_module` in
`lib/eval/eval.ml`) — the typechecker side is the one to audit here.

## Why it matters beyond the suite

The CLI compiles one module per process, so this is invisible there. It is not
invisible to the LSP (re-checks a document repeatedly in one long-lived
process), the REPL/JIT (one check per fragment), or `forge` building several
files. A diagnostic that depends on what was checked earlier in the session is
a real defect in those; whether the leak reaches anything beyond this one note
is exactly what the audit should establish.

## Test-suite hazard until then

A new test declaring a plainly-named record (`A`, `Thing`, `{ a : Int }`) can
silently change an unrelated test's result. `test/test_cap_unforgeable.ml`
carries a comment saying so at the tests that tripped it.
