# Finding 3 closed: `desugar.ml`, `lower.ml`, `perceus.ml` decomposed

**Date:** 2026-08-27
**Plan:** `specs/plans/2026-08-27-lower-desugar-perceus-decomposition.md`
**Closes:** finding 3 of `specs/2026-08-25-file-decomposition-analysis.md` — the three
sizeable, actively-edited pass files that never got a decomposition phase.

| File | Before | After | New module | Lines |
|---|---:|---:|---|---:|
| `lib/desugar/desugar.ml` | 3,320 | 2,141 | `desugar_derive.ml` | 1,213 |
| `lib/tir/lower.ml` | 2,000 | 1,046 | `lower_expr.ml` | 1,010 |
| `lib/tir/perceus.ml` | 1,997 | 743 | `perceus_core.ml` | 1,289 |

Every move is verbatim: the extracted band's comment-stripped code, spliced back at its
re-export site, reproduces the original sequence **in order**. `desugar.ml` and
`perceus.ml` diffed empty; `lower.ml`'s only delta is four aliases
(`ty_of_span`, `fresh_name`, `fresh_var`, `resolve_iface_method`) that the band alone
used and that `lower.mli` does not export, so they moved instead of being kept as dead
re-exports.

## Two composition styles, chosen per file

- **Alias re-export** (`let lower_expr = Lower_expr.lower_expr`) for `lower.ml` and
  `desugar.ml`, matching what the `Lower_*` family already did. Correct where the
  `.mli` does **not** export the moved names.
- **`include Perceus_core`** for `perceus.ml`, matching `typecheck.ml`. Correct here
  because `perceus.mli` exports `env` as a **concrete record** plus ~18 values; aliasing
  would have meant repeating the 123-line record in a second place.

## Two things that had to travel with their band

- **`Lower_match.install_lower_expr`** breaks the `Lower_expr` ↔ `Lower_match` cycle (2
  call directions, 5 edges) and must run *after* `lower_expr` is defined. Left in
  `lower.ml` it still builds, while installing the ref from a module that no longer
  defines the function. Asserted on comment-stripped code: 1 in `lower_expr.ml`, 0 in
  `lower.ml` — a plain `grep` reports 2/2, because the prose in both files names it.
- **`_rc_fresh_ctr`** moved with `fresh_rc_var`, its only producer. Its reset stays in
  `Perceus.perceus` and, through the `include`, is the same ref cell — so `$rc_N`
  determinism, which the TIR golden snapshots depend on, is preserved. The snapshots
  passing is the evidence, not inspection.

## Declined, with reasons

- **`desugar.ml`'s `~H` sigil cluster** (`:105–693`, 589 lines) calls *forward* into
  `desugar_expr` (3) and `desugar_module` (1). Extracting it needs a second forward-ref
  hook of the `install_lower_expr` kind — not worth 589 lines.
- **`desugar.ml`'s qualification tail** (`:2857–3320`, 464 lines) needs 13 names from
  above *and* defines the public `desugar_module`; it cannot sit on either side without
  a cycle, short of turning `desugar.ml` into a re-export shell.

## Oracle notes for whoever edits these files next

**`ir-oracle` cannot certify the derive band.** Three plausible perturbations of
`derive_impl` are INERT — renaming the generated `to_json`, renaming the derived `eq`
method, and reversing `impl_methods` — because those names are discarded downstream. All
three return IDENTICAL on a corpus that does contain `derive Json` and `derive Eq`
programs, so an IDENTICAL result from them proves nothing. The probe that *does* go RED
is structural: make `derive_impl` emit no decls, which fails `ir-oracle`
(`native_nested_derive_json`) and `stdlib_march` (`json_typed`).

Also: `test/run_snapshots.exe` is **not** run by `scripts/run-tests.sh`, and it is the
thing that pins lowering/RC IR shape. Run it explicitly for any change in this area.

## Verification (each task, independently)

- splice check, ordered, comment-stripped — as described above
- `ir-oracle` IDENTICAL across 241 programs, **proven RED first** on each file
  (`fresh_name` prefix → `bench_rrb_bench`; `$rc_%d` prefix → `native_sched_stress`)
- `types-oracle` Tier 1 (601 fixtures) + Tier 2 (7,252 diagnostic lines) IDENTICAL for
  the `desugar.ml` task, which is the one that can move spans
- `test/run_snapshots.exe`: 33 tests
- `bench/tree_transform.march` compiled `--opt 2`, same-box A/B against a compiler built
  from the parent commit: 0.80/0.54/0.54s vs 0.81/0.53/0.54s, identical output
- full build including `lsp/bin/main.exe` and every test executable
- `scripts/run-tests.sh`: 3,177 tests, all suites passed, exit 0
