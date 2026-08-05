# `--cap-strict`: `needs` as a hard ceiling

Shipped 2026-08-04. Opt-in build gate: every module's emitted code must stay
within that module's own `needs` declarations.

```
$ march --cap-strict --compile -o app app.march
-- CAPABILITY CEILING --
module `HostileDep` uses `IO.FileRead` but does not declare `needs IO.FileRead`

--cap-strict: 1 capability ceiling violation(s).
```

## The hole this closes was bigger than believed

The premise going in was "direct builtin calls are a warning, not an error."
Measured, the routes to a capability do not agree with each other:

| route | before |
|---|---|
| direct builtin `file_write(…)` | warning (Check 1b) |
| **stdlib `File.write(…)`** | **nothing at all** |
| builtin passed as a value, called indirectly | nothing |
| user module via `use` | error (Check 4) |
| `extern` block | error (Check 5) |

The stdlib route — the most common one in real code — produced **zero**
diagnostics, because Check 4 walks `DUse` declarations and stdlib modules are
ambiently available without one. `mod M` calling `File.write` with no `needs`
at all typechecked silently, rc=0.

So flipping Check 1b to an error would have closed the smaller hole and left
the larger one open, at the cost of a fifth source-level AST walk — in a
codebase that has already shipped five capability decl-walks whose catch-all
arm silently skipped a declaration form.

## The rule

For every module M: every capability attributed to M must be subsumed by one
of M's own `needs`.

Checked against `March_tir.Cap_attrib` output — emitted code — so all routes
collapse into one rule and re-routing a call through a helper or a wrapper
cannot evade it. Because attribution charges stdlib-mediated IO to the calling
module, this asks nothing of the standard library's own declarations: the
module that called `File.write` is the one required to declare
`needs IO.FileWrite`. The "20 stdlib needs" question never enters the path.

## Why it does not need the dependency to opt in

March dependencies are distributed as source, so attribution is computed from
the consumer's own build of the dependency's code. The check runs on every
module in the program, including dependencies that never heard of the flag.

Measured end to end: a dependency declaring only `needs IO.Console` whose
`greet` reads `/etc/passwd` builds clean today (rc=0, one non-blocking
warning) and fails under `--cap-strict` (rc=1), naming `HostileDep`.

That is the difference between a `needs` declaration you trust and one you
check.

## Two bugs found by testing, not by reading

- **The entry module always read as undeclared.** Desugar unwraps the entry
  module (`~is_entry:true`), so it has no `DMod` and never lands in
  `module_caps`; its `needs` accumulate in `mod_needs`. The first run of the
  check reported a violation against a module that had correctly declared the
  capability. Fixed by binding `(tm_name, mod_needs)` into the map.
- **The fail-closed rule was dead code.** A builtin passed as a *value*
  (`apply1(file_read, p)`) is a TIR *atom*, not an `EApp`, so the walk saw
  nothing and emitted an `IO.FileRead` marker with no owner — and strict
  passed it. `Cap_attrib` now scans atoms in every position, charging the
  capability to the module that hands out the authority. This is the right
  answer on the merits, not just a way to make the check fire.

The second one is the reason the walk is now exhaustive over `Tir.expr` by
construction rather than ending in a catch-all.

## Caching

`--cap-strict` is in `cas_flags` at BOTH sites, and the check runs before the
CAS artifact lookup. Verified: a non-strict build that populates the cache,
followed by a strict build of the same source, still fails (rc=1, 2
violations) rather than being served the cached artifact — the
`--refine-report`-on-a-warm-CAS failure mode.

## Where the code is

- `lib/caps/cap_ceiling.ml` / `.mli` — the rule, with `Undeclared` and
  fail-closed `Unattributed` violations
- `lib/tir/cap_attrib.ml` — atom scanning (the value-passing route)
- `bin/main.ml` — `--cap-strict`, the pre-CAS call site, `cas_flags`
- `test/test_cap_ceiling.ml` — 7 unit tests for the rule (including both
  subsumption directions) and 6 end-to-end tests, one per route plus the
  dependency case and two accept cases

## Follow-ups closed the same day

- **The `println` inconsistency was root-caused**, and was never about
  `println`. `prelude.march` is unwrapped into global scope, so its decls are
  prepended to the ENTRY module's list; Check 1b keeps the first span per
  capability; that span was in prelude; the driver filters stdlib spans. The
  warning was generated and discarded. In practice this only ever hid
  `IO.Console` — `println`/`print` are the only cap-bearing builtins prelude
  calls, so filesystem/network/process warnings were never affected, and the
  same code in a nested module or actor handler warned correctly (which is
  why the existing enforcement tests passed). The mechanism was general
  though: any future prelude addition would have suppressed a real one. Fixed
  via `Typecheck.stdlib_source_files`.
- **No `ECallPtr` witness exists** among the shapes tried (builtin returned
  from a branch, stored in a `Cons` and matched out, called through a
  parameter). The atom scan catches a capability where its name is
  *mentioned*, and a capability must be named to be obtained.
  `Unattributed` remains a backstop with no known trigger.
- **`forge cap inspect --strict`** ships: binaries carry
  `__march_capdecl_<CAP>__<OWNER>` alongside `__march_capfrom_`, so the
  ceiling is re-checkable on an artifact you did not build.

## Open

See `specs/todos/2026-08-04-cap-ceiling-follow-ups.md`: `--cap-strict` is
build-only (not available to `--check`), there is no migration autofix, and
per-dependency budgets still need the module→package roll-up.

For what a *provable* sandbox would additionally require — and why the
artifact channel is the complement to a type-system proof rather than a
substitute for it — see `specs/2026-08-04-provable-sandbox-design.md`.
