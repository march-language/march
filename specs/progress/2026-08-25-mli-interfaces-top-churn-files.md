# `.mli` files for the four highest-churn compiler modules

Landed 2026-08-25.

Implements Finding 4 of
[`specs/2026-08-25-file-decomposition-analysis.md`](../2026-08-25-file-decomposition-analysis.md):
only 2 of 31 files over 800 lines had an interface, which is both why they grow
unchecked and the cheapest available remedy. Four now do.

## What landed

One `.mli` per file, one commit each, no `.ml` line moved and no call site
adjusted. Where a value had a caller anywhere — including a test — it was
exposed and the interface says so; nothing was hidden by editing a consumer.

| File | Inferred vals | Curated vals | Internal |
|---|---:|---:|---:|
| `lib/desugar/desugar.ml` | 69 | 11 | 84% |
| `lib/tir/lower.ml` | 41 | 21 | 49% |
| `lib/tir/llvm_emit.ml` | 114 | 44 | 61% |
| `lib/typecheck/typecheck.ml` | 243 | 50 | 79% |
| **total** | **467** | **126** | **73%** |

"Inferred vals" is the maximal interface `ocamlfind ocamlc -i` prints — what
each module exported before this change. Roughly three quarters of the compiler
surface in its four most-edited files was accidental.

## Method

For each file: generate the maximal interface, then keep a value only if a
sweep of `bin/ lib/ lsp/ forge/ test/ js/` finds it referenced from outside the
module — qualified (`Desugar.x`), through a module alias (`Tc.x`, `TC.x`,
`T.x`), or bare inside a `let open`. Doc-comment mentions were discarded by
hand; alias and `let open` uses are the two the first sweep missed, and both
turned into build errors that named the missing value exactly, so `dune build
@check` was the real oracle.

## What the numbers hide

`lower.ml`'s 49% is the weakest result and the most informative. The Wave-3
split turned it into a re-export hub — `let lower_ty = Lower_types.lower_ty` and
some forty siblings — kept bare "so external callers keep working". Most of
those callers don't exist. But hiding a re-export nothing calls makes it an
unused-value error under warnings-as-errors, so three had to be declared anyway
with a comment saying they are not API. `llvm_emit.ml` has the same problem
thirty-three times over: its real public surface is 11 values, not 44. Deleting
those dead `let` re-exports (and their `val`s) is an obvious, separately safe
follow-up.

`llvm_emit.emit_expr` — the 4,319-line function the file exists for, 76% of it
by line count — has no external caller at all. The sibling emitters that need it
receive it as a labelled `~emit_expr` callback threaded from inside.

## Verification

`scripts/ir-oracle.sh` ran once as a baseline and four times as a check, one
per file: **IR IDENTICAL across 240 programs** every time, never anything else.
Adding an interface must not change emitted code, and it did not.

Also per file: `dune build @check` (no new errors beyond the 19 pre-existing
missing-dev-dependency ones in `forge/test/` and `js/`), `dune build
bin/main.exe`, and `scripts/run-tests.sh`. The `lower.mli` run had one
`run_codegen` fixture killed by SIGKILL (exit 137) — another session's process
sweep on this shared box, not a regression; it passes on rerun.

## Follow-ups

- Delete the dead re-export `let`s in `lower.ml` (3) and `llvm_emit.ml` (33)
  together with their `val`s.
- The remaining oversized files in the analysis table have no interface either;
  `eval.ml`, `bin/main.ml` and `lsp/lib/analysis.ml` are the next candidates by
  the same cheap method.
