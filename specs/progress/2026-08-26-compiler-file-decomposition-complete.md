# Compiler file decomposition — Phases 0–7 complete (2026-08-26)

`specs/plans/2026-08-19-compiler-file-decomposition.md`, executed 2026-08-25/26.

## Result

| File | Before | After | |
|---|---:|---:|---|
| `lib/typecheck/typecheck.ml` | 14,957 | **8,272** | −45%, six modules peeled from below inference |
| `lib/eval/eval.ml` | 12,264 | **4,304** | −65%, seven modules |
| `lsp/lib/analysis.ml` | 8,132 | **5,201** | −36%, four modules |
| `lib/tir/llvm_emit.ml` | 5,719 | **2,271** | −60%; `emit_expr` alone 4,319 → 1,394 |
| `lib/refinecheck/refine_check.ml` | 7,416 | 7,582 | navigation phase — headers + `check_call` 13 params → 8 |
| `bin/main.ml` | 5,402 | 5,429 | not split by design; two CAS-key sites → one |

27 new modules. Three refactor oracles now exist (`ir-oracle`, `refine-oracle`,
`types-oracle`) — see CLAUDE.md for what each does and does not cover.

## What was skipped, deliberately

- **Phase 6 tasks 6.7/6.8** — moving that band changes module-initialisation
  order, and no oracle in the plan can see a regression there.
- **Phase 2's arm consolidation** — non-builtin arms interleave with builtin
  ones, so hoisting flips TCO precedence and fall-through; no corpus program
  exercises either, so the oracle would have shown IDENTICAL for a real break.
- **90 of `emit_expr`'s 133 arms** stay inline: each is 3–10 lines, shorter than
  the call that would replace it.
- **`infer_expr`'s recursion group** (2,217 lines, 14 mutually recursive
  functions), `check_decl` + the module entry point, and §12 linearity — all
  concluded not worth decomposing, with reasons, in the Phase 6 plan.

## The plan was wrong more often than the code was

Recorded because it is the transferable lesson. Every item was found by
re-deriving rather than trusting:

- **Its own IR oracle could never run** — a `${1:?… {a|b} …}` bash expansion
  ends at the first `}`. A 2026-08-23 review had certified it "verified and
  unchanged". The same bug sat in the refine-oracle script and would have
  shipped a second dead oracle.
- **31 hard-coded line ranges and 15 counts were stale**; a `sed` against a stale
  range mangles code while tests still pass.
- The builtin count was given as 50 in one place and 58 in another; it is **57**.
- Task 2.2 specified a codegen branch for a **second `task_await` arity that does
  not exist**, and would have given `root_cap` a variant constructor although it
  dispatches in `emit_atom`.
- Task 4.1 stated `ast_code_actions` is *appended*; it sits in the **middle** of
  the concatenation with four groups after it. Following the plan would have
  silently reordered the code actions users see.
- Task 6.6 Step 1 is **not executable** — `warn_unused_params` sits between the
  band and its dependency.
- Phase 6's own baseline said `infer_expr` is 1,500 lines; the **recursion group
  is 2,217**, and the group is the unit that must move.

## Method notes worth keeping

- **Machine-check verbatim-ness; never assert it.** Read each moved region back
  *out of the destination file*, substitute at its call site, require byte-for-byte
  equality with the original. This caught a `.rstrip('\n')` that silently dropped a
  trailing blank line per block.
- **That proof shows motion fidelity, not band correctness** — it proves you moved
  what you selected, not that you selected the right thing. An off-by-one from a
  printed `sed` excerpt slipped past it; the build caught it. Choose bands by anchor.
- **`open` does not re-export — use `include`.** Consumers reach modules through
  `let open` and aliases, which no grep can see. `dune build @check` is the only
  reliable oracle for that class.
- A `dep.py`-style scan reporting zero dependencies is **not** a completeness
  proof: reading one file cannot see a band's dependency on an already-extracted
  module.
