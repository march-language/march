# Target B — `lib/typecheck/typecheck.ml` decomposition, tasks B1–B5 (2026-08-27)

`specs/plans/2026-08-27-remaining-decomposition-targets.md`, Target B, executed
2026-08-27. All five tasks landed.

## Result

| | Task | New module | Lines | `typecheck.ml` after |
|---|---|---|---:|---:|
| B1 | declaration dependency ordering | `typecheck_reorder.ml` | 512 | 7,787 |
| B2 | module-level `cap` checkers | `typecheck_modcaps.ml` | 418 | 7,404 |
| B3 | §1 unification + §2 surface-type conversion | `typecheck_unify.ml` | 844 | 6,627 |
| B4 | session-type projection and duality | `typecheck_session.ml` | 229 | 6,430 |
| B5 | fix the stale §7 header (comments only) | — | — | 6,448 |

`lib/typecheck/typecheck.ml`: **8,272 → 6,448 lines (−22%)**, four new modules.
B5 adds 18 lines back, all of them comment.

`lib/typecheck/typecheck.mli` was **unmodified** through B1–B4 — the whole point
of `include`-not-`open`. B5 touches only its section docstring.

## The module-initialisation-order blocker was void, and it stays void

Phase 6 gated tasks 6.7/6.8 on this: the B3 band contains both of this
library's top-level effects, and no oracle can see a reordering. The oracles
still cannot. The hazard, on inspection, is not there:

- **The whole init-order surface of `lib/typecheck/` is two lines.** Eight
  modules, two `let () =`, and both are the hook installations in question.
- **`inject_iface_exports_ref` has no reader.** Declaration
  (`typecheck_env.ml`), installation, two comments, one `.mli` line — and no
  dereference anywhere in `lib/ lsp/ bin/ forge/ test/`. An installation
  nobody reads cannot have an ordering regression. Filed separately as
  `specs/todos/2026-08-27-inject-iface-exports-hook-has-no-reader.md` and
  deliberately left in place as a breadcrumb; not fixed here.
- **`expand_record_ref` moves as a closed unit.** Its declaration, its single
  dereference (inside `unify`) and its installation were all three inside the
  B3 band and are all three now in `typecheck_unify.ml`, in that order.
  `Typecheck_unify` initialises strictly before `Typecheck`, so the install
  still precedes every possible read — strictly safer than before.

### The standing assertion, in runnable form

Re-run these whenever `lib/typecheck/` is touched. They are the substitute for
the oracle that cannot exist.

```bash
# 1. exactly two top-level effects in the whole library
grep -n '^let () =' lib/typecheck/*.ml | wc -l                    # 2

# 2. the record-expansion hook's three CODE sites, all in one file,
#    in declaration -> read -> install order
grep -nE '^let expand_record_ref|!expand_record_ref|^let \(\) = expand_record_ref' \
  lib/typecheck/typecheck_unify.ml                                # 3 hits
grep -cE '^let expand_record_ref|!expand_record_ref|^let \(\) = expand_record_ref' \
  lib/typecheck/typecheck.ml                                      # 0

# 3. the other hook still has no reader
grep -rn '!inject_iface_exports_ref' lib/ lsp/ bin/ forge/ test/  # no hits
```

**If assertion 1 ever returns more than 2, the argument above expires and the
hazard is live again** — whatever adds the third effect owes a real init-order
test.

Note the shape of assertion 2. The plan wrote it as
`grep -c 'expand_record_ref' typecheck_unify.ml # must be 3`, which reports
**7** once the file has a doc comment: a bare count also picks up prose
mentions. A first draft of B3 put the fix inside the file's own header, where
the literal pattern matched itself and inflated the count it was meant to pin.
The invariant lives in the header as prose; the runnable command lives here.

## Shared-mutable-cell probe (B3)

`bin/main.ml` marshals `Typecheck._counter` and `._record_names` into the
stdlib typecheck-env cache, so a *duplicated* cell reproduces the cross-run
nondeterminism of
`specs/progress/2026-08-24-interp-perf-phase-3-startup-tcenv-cache.md`. Nothing
in the B3 band declares those cells, but the probe ran anyway — it is the
failure this library has actually had.

`--emit-core-ast` on an accepting program under a private `HOME`, cold then
warm then cold-under-a-fresh-`HOME`: byte-identical (17,374 bytes), all exits
0.

**The probe was also shown non-vacuous rather than merely green**: 1,224 ms
cold, 216 ms warm, 1,235 ms again once the 6 MB `stdlib_tcenv_cli_*.bin` is
truncated. The cache is genuinely on the read path, so cold == warm is a real
assertion and not a comparison of two cold runs.

## Two dependencies the plan's per-band scan missed

The plan's table called B2 and B4 dependency-free in both directions. Each was
one name short, and in both cases the build caught it on the first compile:

- **B2** — `is_nondeterministic_cap` reads `builtin_cap_table`
  (`Typecheck_builtins`).
- **B4** — `project_protocol` calls `unfold_srec` (`Typecheck_exhaustive`).

Both are *unqualified value* references, which a module-prefix grep cannot
see. This is the same blind spot the Phase 6 notes flag for `dep.py`: a scan
reporting zero dependencies is not a completeness proof. Both were fixed by
adding the module to the new file's includes, at a position `Typecheck`
already included it, so no order changed.

## Method

- **Code motion only.** Definitions moved verbatim; no renaming, no
  reformatting, no drive-by fixes. B5 is comments only and is its own commit.
- **Verbatim-ness machine-checked, never asserted.** Each moved band was read
  back *out of the destination file on disk*, substituted at its `include`
  site, and required to reproduce the original `typecheck.ml` byte for byte;
  each band was also asserted comment-balanced outside string literals.
- **Bands chosen by anchor, never from a printed excerpt**, and every range
  re-derived by grep at the moment of use — line numbers shift under your own
  earlier commits.
- **B5's comment-only claim was proven, not asserted**: OCaml comments were
  stripped (nesting- and string-literal-aware) from the before and after of
  both `typecheck.ml` and `typecheck.mli`, and all 4,111 / 308 surviving
  non-blank code lines matched in text, indentation and order. The check was
  first shown to go **RED** on a one-line injected code change, so the green
  means something.

## Verification

Every task ran the same gates, all against baselines recorded before the first
edit. **No oracle was ever non-IDENTICAL, at any task.**

| Gate | Result, every task |
|---|---|
| `scripts/types-oracle.sh` Tier 1 | CORE-AST IDENTICAL (601 fixtures) |
| `scripts/types-oracle.sh` Tier 2 | DIAGNOSTICS IDENTICAL (7,252 lines / 601 fixtures) |
| `scripts/ir-oracle.sh` | IR IDENTICAL across 241 programs |
| `scripts/refine-oracle.sh` | REFINEMENT DIAGNOSTICS IDENTICAL (5,476 lines / 298 fixtures) |
| `scripts/run-tests.sh` | 11 suites / 3,161 tests, exit 0 |
| `dune build --root . @check` | the same 17 pre-existing errors (`forge/test/*`, `js/*`) |
| `grep -n '^let () =' lib/typecheck/*.ml \| wc -l` | 2 |

`refine-oracle` was run for B2 (the panic-surface band interacts with
`cap no_panic` / panic-surface-by-proof), B3, B4 and B5. B4 used the **full**
suite as the plan requires — session types have `Slow` suites; 75 test lines
naming session / protocol / duality cases ran.

`@check` is the only gate that sees `let open` and the `Tc.` / `TC.` / `T.`
aliases, which no grep can. Its 17 errors are pre-existing and unrelated
(missing `Alcotest` and `March_eval` under `forge/test/` and `js/`); they were
baselined first and compared as a **set**, because dune emits them in a
different order run to run.

`scripts/check-docs.sh` passes after B5.

## What was deliberately not done

Unchanged from Phase 6, and still right: **`infer_expr`'s recursion group**
(2,215 lines, 14 mutually recursive functions) is one unit — moving it moves a
quarter of the file into a module that must then `include` back almost
everything. **`check_decl`** and **§8 the module entry point** both call into
that group. `typecheck.ml`'s remaining 6,448 lines are essentially that knot
plus its immediate consumers.

The `inject_iface_exports_ref` dead hook is **left in place**; giving it a
reader or removing it is its own decision, tracked in its own todo.
