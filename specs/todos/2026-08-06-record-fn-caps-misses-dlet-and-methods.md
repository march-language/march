# `record_fn_caps` gives no `own(...)` entry to `DLet` bodies, interface methods, or impl methods

**Filed:** 2026-08-06, while landing demand-driven Check 4 propagation
(`specs/progress/2026-08-06-demand-driven-cap-propagation.md`). This is the
design doc's own open question
(`specs/2026-08-06-per-function-capability-closure-design.md`, "Open questions")
turned into a concrete, now-load-bearing defect.

## The gap

`record_fn_caps` (in `check_module_needs`, `lib/typecheck/typecheck.ml`) is
driven by `used_caps` / `body_cap_uses` / `extern_cap_uses`, which between them
cover `DFn` signatures and bodies, actor handlers, and `DExtern`. They do **not**
cover:

- module-level `DLet` binding bodies,
- `DInterface` default methods,
- `DImpl` methods.

Those names get no entry in `env.own_cap_closures`, so
`fn_transitive_capability_closures` returns `[]` for them — and, worse, returns
a **silently truncated** closure for anything that references them.

## Why it matters now

Until 2026-08-06 the table was analysis-only. Check 4 now consults it, so the
truncation can drop a capability the compiler previously required. Two cases,
only the first of which is guarded:

| Shape | Guarded? |
|---|---|
| The importer references the entry-less name **directly** (`import M` then `M.some_let`) | **Yes** — `import_required_caps`'s `caps_of_name` finds no entry and falls back to the imported module's whole declared `needs` set, i.e. the pre-change answer. Pinned by `cap-closure` test `a name with no closure entry falls back to module caps`. |
| The importer references a `DFn` that itself **reaches** an entry-less form | **No** — the `DFn` has an entry, so `caps_of_name` succeeds and returns its truncated closure. The fallback never fires. |

So: `mod M do needs IO.Console; let banner = ...print...; fn greet() do banner end end`
— an importer referencing only `greet` may no longer be required to declare
`IO.Console`, where before this change it was. That is the "promises something
and does not deliver" direction, which the plan's global constraints call as
serious as a false positive.

Bounded, but not zero: it needs the referenced `DFn` to reach a capability
*exclusively* through one of the three uncovered forms. Any path through an
ordinary `DFn` or builtin call is still counted.

## Shape of the fix

Give the three forms an `own(...)` entry the same way `DFn` gets one — extend
the `decls` walks that feed `record_fn_caps` (and `record_fn_refs`, so the
reference edges are there too) to include `DLet` binding bodies, `DInterface`
method bodies, and `DImpl` method bodies, keyed consistently with the existing
`cap_qname_prefix` scheme.

Watch for: the `march caps` cross-check
(`test_transitive_cap_union_matches_module_level`) compares the transitive union
against `fn_own_capability_closures`, so both tables must gain the same entries
or that test will (correctly) go red. Adding entries can only *increase* what
Check 4 requires, so this fix is **not** in the strictly-loosening class —
re-run the corpus sweep and the scratch positive control, and expect the
possibility of genuinely new errors on code that under-declares today.

## Related

- Blocks a confident re-measurement of Step 4's blast radius
  (`specs/2026-08-06-per-function-capability-closure-design.md`, "Step 4"),
  since the 176-file figure was measured before any of this.
- The `KEEP IN SYNC`-style note lives on
  `fn_transitive_capability_closures_tbl`'s docstring in
  `lib/typecheck/typecheck.ml`, and the user-facing statement is in
  `docs/capabilities.md` + `specs/lang/capabilities.md`.
