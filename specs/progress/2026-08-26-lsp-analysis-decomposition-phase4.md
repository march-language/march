# `analysis.ml`: split the code-action engines — Phase 4

**Date:** 2026-08-26
**Plan:** `specs/plans/2026-08-19-compiler-file-decomposition.md`, Phase 4
**Branch:** `claude/lsp-analysis-phase4`

## What landed

Three commits, all pure code motion.

| file | lines |
|---|---|
| `lsp/lib/analysis.ml` | 8,132 → **5,201** |
| `lsp/lib/analysis_types.ml` | new, **302** |
| `lsp/lib/analysis_util.ml` | new, **574** |
| `lsp/lib/code_actions_ast.ml` | new, **1,097** |
| `lsp/lib/code_actions_diag.ml` | new, **1,019** |

No consumer changed. `Analysis.code_actions_at` keeps its exact signature
(`~line ~character ?diagnostics ()`, trailing unit included), and every other
moved name — `Analysis.t`, `Analysis.rename_at`, `Analysis.references_at`,
`Analysis.apply_fix_registry`, … — keeps working, because `analysis.ml`
re-exports the new modules with `include`. `lsp/lib/server.ml` and the 43
`An.code_actions_at` call sites in `lsp/test/test_lsp.ml` are untouched.

## The plan said two modules; it needs four

Phase 4 as written creates `code_actions_ast.ml` and `code_actions_diag.ml` and
nothing else. Its own Step 2 hedges the reason that is not enough: `type t` is
defined in `analysis.ml` (`:189`), so a module that opened `Analysis` to name
`t` would close a dependency cycle. What Step 2 does not say is that `t` is not
the only thing the engines reach back for. The two engines call **37** top-level
definitions defined earlier in `analysis.ml` — `find_uses`, `iter_expr`,
`lambda_free_vars`, `collect_lambda_captures`, `perf_insight_to_diag`,
`offset_of_pos`, `slice_span`, `smallest_expr_at`, `find_end_before_span`, the
`fix_gen`/`fix_registry`/`apply_fix_registry` trio, the `surface_ty` family, and
(transitively, via a rename quick fix) `rename_at → references_at →
symbol_spans_at → locations_of_spans / local_symbol_at / span_in_user_file`.

So the split is:

- **`analysis_types.ml`** — the five module aliases plus every result type up to
  and including `type t` (original lines 13–299).
- **`analysis_util.ml`** — `include Analysis_types` plus the transitive closure
  of what the engines reach, computed mechanically rather than by eye.
- **`code_actions_ast.ml`** / **`code_actions_diag.ml`** — `open Analysis_util`
  and the two engines, verbatim.
- **`analysis.ml`** — `include Analysis_util` near the top, `include
  Code_actions_diag` where `code_actions_at` used to be.

`lsp/lib/dune` has no `(modules …)` field, so all four files were picked up with
no dune edit — unlike `lib/tir` and `lib/refinecheck`, which do carry explicit
lists that silently drop new files.

## `ast_code_actions` is spliced, not appended

The plan's Step 5 proposes

```ocaml
Code_actions_diag.actions … @ Code_actions_ast.actions …
```

That would **reorder the returned actions**. The single call site is at
`analysis.ml:7755`, in the *middle* of `code_actions_at`'s concatenation:

```
… @ batch_fix_all_actions
@ ast_code_actions a ~line ~character
@ registry_actions @ html_close_actions @ parallelize_actions @ refine_actions
```

Four action groups follow it. So `code_actions_diag.ml` does `open
Code_actions_ast` and keeps that line untouched, and `analysis.ml` republishes
the whole thing with `include Code_actions_diag`. Order is unchanged by
construction rather than by inspection.

## Verbatim-ness is machine-checked

`ir-oracle.sh` and `refine-oracle.sh` prove **nothing** here — LSP code is never
emitted as LLVM IR and never emits a refinement diagnostic. The proof used
instead is a reassembly: walk the original 8,132-line `analysis.ml` top to
bottom and consume each line from whichever of the five resulting files matches
next, preferring the longest run. Result:

```
unconsumed lines per source: {'analysis': 0, 'types': 0, 'util': 0, 'ast': 0, 'diag': 0}
lines attributed: analysis 5190, types 293, util 563, ast 1085, diag 1001  (sum 8132)
added: 10 glue lines (two comments + two `include`s), 1 blank line
```

Every original line is present exactly once, byte-identical, in order. The one
added blank line is the separator that used to sit between the two engines,
which are no longer adjacent.

Two traps were hit while building the extractor, both worth remembering:

1. **A doc comment containing a blank line** breaks naive "walk back over the
   preceding comment lines" logic — it stops at the blank and the previous
   definition's range swallows the first half of the comment. The fix is to use
   a real nested-`(* *)` mask and treat a blank line as part of a comment when
   the mask says it is. A balanced-comment assertion on every range before
   writing it caught this (`clause_param_names`, `analysis.ml:1492–1508`).
2. **Trailing blank lines are content.** Writing each extracted block with
   `.rstrip('\n') + '\n'` silently dropped one line per block; the reassembly
   check found it, an eyeball would not have.

## Verification

`scripts/run-tests.sh` **does not cover the LSP** — its `ALL_RUNNERS` list is
`compiler eval codegen stdlib stdlib_march test_jit`, with no LSP suite at all.
Running it and declaring victory would test nothing relevant to this change. The
real gates are the five executables under `lsp/test/`, run directly:

| suite | tests | before | after |
|---|---|---|---|
| `test_lsp` | 354 | pass | pass |
| `test_utf16` | 5 | pass | pass |
| `test_jsonrpc` | 22 | pass | pass |
| `test_incremental` | 10 | pass | pass |
| `test_query_cli` | 7 | pass | pass |

`test_jsonrpc` spawns `lsp/bin/main.exe` over stdio, so it reports **22
failures** unless that binary has been built — a `dune build lsp/test/…` alone
is not enough. Build `lsp/bin/main.exe` explicitly before believing a red run
there.

The LSP suites are also **cwd-sensitive**: run `test_lsp.exe` from `/tmp` and
"introduce pipe offered" fails. Setting `MARCH_STDLIB` does *not* fix it — the
fixtures resolve relative to the invocation directory, not just the stdlib. Run
them from the repo root.

`dune build --root . @check` (which typechecks `test/` and `lsp/`) sits at
**17 errors both before and after**, all pre-existing, all under `forge/test/`
and `js/` from a missing optional opam dependency. `scripts/run-tests.sh` was
also run to confirm nothing outside the LSP moved: 2,763 tests, exit 0. With
the LSP suites now included (below) a full `scripts/run-tests.sh` is **3,161
tests across 11 suites**, exit 0.

One caution from doing that: **do not edit `scripts/run-tests.sh` while it is
running.** bash re-reads a script from a byte offset, so an edit mid-run
corrupts the tail of the executing instance — the first full run here ended in
`line 167: ib: command not found`, exit 127, after every suite had actually
passed. The verdict was garbage; it had to be redone.

## Also landed: LSP suites in `scripts/run-tests.sh`

Separate commit. `ALL_RUNNERS` grows from six to eleven, and the exe path
becomes per-runner because the LSP suites live under `lsp/test/`, not `test/`;
`lsp/bin/main.exe` is added as an explicit build target when `test_jsonrpc`
runs. Shown to actually execute rather than vacuously pass: deleting
`_build/default/lsp/bin/main.exe` and re-running still reports 22 tests, and
renaming a single code-action title in `code_actions_ast.ml` turns the run red.

## Follow-ups not done here

- `analysis.ml` still has no `.mli` at 5,201 lines, and neither do the four new
  modules. `analysis_util.ml` in particular is a grab-bag by construction — an
  interface would be the place to say which of its 37 definitions are really
  shared surface and which are engine-only. Note that an `analysis.mli` has to
  restate what `include Analysis_util` and `include Code_actions_diag` bring in,
  so it is a larger and less obviously-profitable job than the ones in PR #354.
