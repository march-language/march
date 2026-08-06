# Demand-driven import capability propagation (Check 4)

**Landed:** 2026-08-06. Step 3 of
`specs/2026-08-06-per-function-capability-closure-design.md`. Consumes the
per-function transitive closure built in Step 2.

## What changed

`import M` / `use M` used to force **every** capability `M` declares onto the
importer (Check 4, already an ERROR). It now forces only the capabilities of the
functions the importer actually references from `M`.

This is the blocker the design doc names: contracting `List` with `needs
IO.Spawn` (for `pmap`'s `task_spawn`) would otherwise have forced `needs
IO.Spawn` on every module that imports `List` to call `map`, and every March
program would have landed at `needs IO`.

## How

- `import_entry` gained `ie_used_names : (string, unit) Hashtbl.t`.
  `record_use` already knew, at each index hit, exactly *which* imported name a
  reference resolved to; it collapsed that to the `ie_used` boolean and threw
  the name away. It now records it too. The exact-name index records the bare
  name (a rebound short name from `import M`), the prefix index the full dotted
  name (a qualified `M.foo` under `use M`).
- `fn_transitive_capability_closures` was split: the fixpoint now lives in
  `fn_transitive_capability_closures_tbl` (returns the raw `Hashtbl`, O(1)
  lookups) defined **above** `check_module_needs`, with the public sorted
  assoc-list accessor as a thin wrapper at its original position.
- `check_module_needs` gained `import_required_caps`, shared by Check 4 and by
  `module_wide_caps`' `propagated` component. It resolves each recorded name
  against the closure table and **filters** the imported module's declared set
  down to what is demanded.

## Direction: strictly loosening, by construction

`import_required_caps` returns a **subset of `env.module_caps`** for the
imported module — the demand set filters, it never adds. That is not incidental:
returning the demand set directly would have been able to *increase* what an
import costs, because a referenced function's transitive closure can contain a
capability the imported module never declared (Check 1b only WARNS about a
capability builtin called directly in a body). Propagating that outward would
have been a brand-new error on code that compiles today. The filter keeps a
declared cap `c` when some referenced function demands a `d` related to it in
either direction (`cap_subsumes c d || cap_subsumes d c`), so an umbrella
`needs IO` is still kept by a demanded `IO.Console`.

## Fail-open guards

`record_fn_caps` populates `own_cap_closures` for `DFn`s, actor handlers and
externs, but **not** for module-level `DLet` bindings, interface methods or
`impl` methods. Those names have no entry, so their closure is empty — and
reading "no entry" as "no capabilities" would have silently dropped enforcement
that exists today. Three fallbacks to the whole-module set, all conservative:

1. a referenced name with no closure entry;
2. an import that filed no tracker entry at all;
3. a cyclic module pair, where the module topological sort (which tolerates
   cycles rather than rejecting them) has not yet analyzed the imported module.
   Verified empirically: population is all-or-nothing per module, so the
   not-yet-checked side of a cycle has *no* entries, hits fallback 1, and keeps
   today's behavior. Pinned by `cap-closure` test 13.

The fallbacks are scoped to names in `ie_used_names` — names the index proved
came from *this* import. Applying them to every unresolved reference would catch
every local and parameter and collapse the whole feature back to module
granularity.

## Incidental fix

A single-segment `use Foo` rebinds nothing (every `Foo.bar` short key already
*is* the qualified key), so it filed no import-tracker entry and therefore
tracked no references — leaving demand-driven propagation with nothing to go on
for exactly the qualified-reference form `use` exists to serve. The entry is now
registered unconditionally, with `ie_used` seeded to `new_bindings = []` so the
unused-import warning stays byte-identical (a rebind-nothing `use` never warned,
because it had no entry to warn from).

## Not changed

The Check 4 diagnostic text and its caret span are byte-identical; only the set
of required capabilities narrowed. `march caps` output is unchanged across the
stdlib/bench/native corpus (the closure is built on `own_cap_closures`, not on
`module_wide_caps`, so there is no second source of truth).

## Verification

- `cap-closure` group: 7 new cases. RED before the change showed exactly the
  right split — the three loosening cases failing, all four REJECT controls
  already green. Load-bearing mutation (restore the old over-approximation)
  reproduces that same split.
- Corpus sweep (`stdlib/*.march`, `test/native/*.march`, `bench/*.march`,
  `--check`) against a binary built at the base commit: no diagnostic
  differences at all. The corpus contains no Check-4 errors to begin with, which
  is why the positive control is a scratch fixture outside `stdlib/`
  (`bin/main.ml` filters stdlib-span diagnostics, so a stdlib-internal control
  would produce a false "no diff"): a two-file `Helpers`/`Consumer2` pair under
  `MARCH_LIB_PATH` errors under the base binary (exit 1) and compiles clean
  under the new one (exit 0), while the same consumer referencing the *impure*
  `noisy` still errors with the identical message and caret.

## Next

Step 4 of the design (flipping Checks 1b/1c from warning to error) is
deliberately **not** in scope. Re-measure the blast radius — the 176-file
pre-Step-3 figure should shrink substantially — before deciding.
