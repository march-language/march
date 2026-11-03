# Per-function `needs` bounds, phase 1: syntax and check

Road to 1.0, Pillar 2, option B (decisions of 2026-09-29); sequence in
`specs/plans/2026-11-01-per-function-needs-bounds.md`.

## What shipped

- **Syntax.** `fn f(x) : T needs IO.Console, IO.Clock do`, `needs ()` for the empty
  bound, on `fn`/`pfn` (with or without type-variable bounds) and impl methods. The clause
  follows the return annotation and precedes `when`. Plain capability paths only. AST:
  `fn_def.fn_needs : (name list list * span) option`. The parser's clause merge takes the
  bound from any one clause and rejects two clauses with different bounds. Menhir's
  conflict count is unchanged (7).
- **Checks** (`lib/typecheck/typecheck_caps.ml` `record_fn_bound`,
  `lib/typecheck/typecheck.ml` `check_fn_bounds`):
  - each path is a real capability (`unknown_capability`) within the module's `needs`
    (`cap_bound_needs`);
  - every IO-lattice capability in the function's row is covered by the bound
    (`cap_bound`, with the reach chain);
  - a row with `unknown` (an invocation of a function value of untraceable origin) is
    refused unless the bound includes all of `IO`;
  - `deps` (invoked parameters) are not charged: the supplier pays.
  It is R1 stage C's `check_fn_grants` (removed in #283) re-attached to a declaration.
  Rows with `deps`/`unknown` are solved only when some function declares a bound, so
  every other `--check` keeps the caps-only fixpoint cost.
- Impl methods are recorded under their mangled key, so their bounds are checked too
  (the first draft ignored them silently).
- Formatter prints the clause; tree-sitter grammar (`fn_needs`) with a corpus case.
- Reference: `specs/lang/capabilities.md` "Per-function bounds", surface syntax, the
  threat-model and claim pages (no longer "planned, not built").

## Noise measurement (the plan's fall-back-to-A condition)

Every single-line module-level `fn`/`pfn` header in `stdlib/` was given a bound equal to
its module's `needs` (or `needs ()`), and each module checked: 3247 bounded functions,
**173 `unknown` refusals (5.3%)**, concentrated in combinator and codec modules that keep
functions inside data structures (`seq` 26, `gen` 23, `parser` 19, `flow` 18, `config` 18:
`Codec(_, enc, _)` then `enc(value)`). The 165 reach errors are the synthetic bound being
false (stdlib modules that do not declare everything they reach). The refusals sampled
are real limitations of the analysis, not bugs, and only bite where a narrow bound is
declared over such code, so fallback A is not triggered.

## Tests

`test/test_cap_fn_bounds.ml` (suite `cap_fn_bounds` in run_compiler, 13 cases): direct
and transitive reach (chain named), module containment, lattice direction, unknown
capability, callback not charged, untraceable call refused (and accepted under `needs
IO`), no effect on callers, multi-clause (and conflicting bounds), nested module, impl
method, formatter round trip. Disabling `check_fn_bounds` fails 7 of them; the other 6
cover the recording-time checks, parsing and the formatter.

## Oracles

`scripts/oracle-base.sh types refine` against the merge-base: refine unchanged (297
fixtures); types reports 60 fixtures changed, all synthetic: derived and generated
declarations get spans whose columns are hashes of AST values (`<none>`,
`<work-entry>`, …), and `fn_def` gained a field, so the hashes moved. With every
`"file":"<…>"` span normalised, 58 of the 60 are identical; `reject_t286` differs only in
such a span printed inside an overlapping-impl message, and `reject_t278` lists the same
31 diagnostics in a different order (they sort by those spans). No inference result or
diagnostic changed.

## Next

Phases 2–4: `specs/todos/2026-11-01-fn-needs-bounds-interfaces.md`,
`specs/todos/2026-11-01-fn-needs-bounds-tooling-semver.md`,
`specs/todos/2026-11-01-fn-needs-bounds-hot-reload.md`.
