# Per-function `needs` bounds (road to 1.0, Pillar 2, option B)

Design and decisions: `specs/plans/2026-09-28-road-to-1.0.md`, "Pillar 2 — per-function
bounds (option B, fallback A)", decisions 1–4 of 2026-09-29. This file is the
implementation sequence.

## Semantics (phase 1)

```march
mod Fetch do
  needs IO.NetConnect, IO.Console

  fn fetch(url : String) : String needs IO.NetConnect do ... end
  fn pure_len(s : String) : Int needs () do ... end
end
```

- The clause sits after the return annotation and before `when`/`do`. `needs ()` is the
  empty bound (the function performs no capability). Plain capability paths only; a path
  scope (`IO.FileRead("/etc")`) on a function bound is a later extension.
- **Bounded by the module:** every capability a bound names must be covered by the
  module's `needs` (`declared(f) ⊆ needs(module)`), and must be a real capability.
- **Bounds the body:** every IO-lattice capability in the function's row (`caps`, the
  same transitive closure the module ceiling and `main`'s grant are checked against) must
  be covered by the bound. The error names the chain to the capability.
- **Callbacks** (`deps`): not charged to the bounded function; the caller that supplies
  the callback is charged, as today. So a bound means "my own authority, plus whatever you
  hand me".
- **Untraceable invocations** (`unknown`): a narrow bound over a body that invokes a
  function value of untraceable origin is refused, with a pointer to the call. A bound
  covering all of `IO` claims nothing within the lattice and is not refused.
- **No effect on callers.** A caller's own reach is unchanged; it stays bounded by its
  module and `main`'s grant.
- Multi-clause functions: the bound may be written on any one clause; two clauses
  carrying different bounds is an error (as with return types).

This is the removed R1 stage C check (`check_fn_grants`, deleted in #283) re-attached to a
declaration instead of to `Cap(X)` parameters, which is what forced the threading.

## Phases

1. **Syntax and check** (this PR): AST field `fn_needs`, parser (all `fn`/`pfn` forms,
   menhir conflict baseline unchanged), clause merging, formatter, tree-sitter grammar,
   the two checks above with the `unknown` refusal, error code, reference docs, tests,
   and a noise measurement: bounds declared across a sample of stdlib modules.
2. **Interfaces** (decision 2): a `needs` bound on an interface method signature; every
   impl method checked against it. Plan: `specs/plans/2026-11-02-interface-needs-bounds.md`. The bound
   is a check on impls only, never part of a method's type or a constraint, so it adds no
   capability threading.
3. **Tooling and semver** (decision 3): widening a declared bound is a major bump in
   forge's semver check and appears in `forge audit` upgrade diffs; `forge fix` can write
   the tightest bound; LSP hover shows the inferred row.
4. **Hot reload** (decision 4): a patch that widens a declared bound is refused unless
   the deploy authorises that widening explicitly, and the widening is audited.

Fallback A (module-scoped only) if the phase 1 measurement shows the `unknown` refusals
are too noisy to use.
