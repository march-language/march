# `lib/eval` decomposition: Phase 1's two prerequisite layers landed

Landed 2026-08-25. Implements Tasks **1.0** and **1.0b** of
`specs/plans/2026-08-19-compiler-file-decomposition.md`. The rest of Phase 1
(Tasks 1.1–1.5) is still open; the tracking item stays in
`specs/todos/2026-08-19-compiler-file-decomposition.md`.

## What moved

Two pure code-motion commits, one per task. No renaming, no reformatting, no
behavior change — every definition moved verbatim with its doc comment.

- **`lib/eval/eval_types.ml`** (134 lines) — the interpreter's `value`/`env`
  type block, extracted verbatim from `eval.ml:17-142` (the ring-buffer type,
  `type value`, and the mutually-recursive `chan_endpoint` / `mpst_endpoint` /
  `timer_entry` / `env`). Re-exported from `eval.ml` with **`include
  Eval_types`**, not `open`: `open` would make the constructors visible inside
  `eval.ml` but would *not* re-export them to the `Eval.VInt`-style consumers
  in `lib/repl`, `lib/dap`, `lib/debug`, and the test suite.
- **`lib/eval/eval_prim.ml`** (52 lines) — `exception Eval_error`,
  `let eval_error`, and **all five** late-bound hook refs:
  `http_fetch_hook` (was `eval.ml:894`), `iface_dispatch_hook` (`:1520`),
  `eval_expr_hook` (`:1814`), `run_scheduler_hook` (`:1819`), `apply_hook`
  (`:1824`). Re-exported from `eval.ml` at the original positions —
  `exception Eval_error = Eval_prim.Eval_error` plus one `let` alias per hook.
  Aliasing a `ref` shares the same mutable cell, so `eval.ml`'s startup
  installation (`eval_expr_hook := …`) is unchanged.

The hook list was re-enumerated by `grep -nE '^let [a-z_]*_hook\b'` rather than
copied from the plan: an earlier draft of the plan omitted `http_fetch_hook`.
`call_hook_opt` (`eval.ml:11728`) matches the eye but not the pattern — it is a
function, not a forward-reference ref, and stays in `eval.ml`.

`eval.ml`: **12,264 → 12,128** lines (−136).

`lib/eval/dune` needed no edit — the library uses default module discovery
(`(modules (:standard \ discover_compress))`), unlike `lib/tir` and
`lib/refinecheck`, which carry explicit `(modules …)` lists.

## Why this ordering

`eval_prim.ml` is small but is the layer every later Phase-1 extraction depends
on. `base_env` references `eval_error` ~717 times and the hook refs ~41 times;
`eval_net`/`eval_session`/`eval_simd` reference them too. Because `eval.ml`
will depend on those extracted modules, any reference from them back into
`eval.ml` is a module cycle — a hard compile error. Moving this bottom layer
first gives them somewhere legal to point.

## Verification — and the oracle gap

**`scripts/ir-oracle.sh` is structurally blind to this file.** The interpreter
is never emitted as LLVM IR, so a green oracle proves nothing about any change
under `lib/eval/`. This is stated in the plan (Task 0.3 and the Phase 1
preamble) and is re-recorded here because it is the single most important thing
a future reader of these commits needs to know: do **not** accept a green
`ir-oracle.sh check` as evidence that an `eval.ml` extraction is sound.

The proof used instead:

1. **Full suite.** `scripts/run-tests.sh` → exit 0, 2,760 tests, both before
   (baseline at `f953ac36`) and after. Judged by exit code, not tail output.
2. **The interpreter-performance control.** The failure mode a code move can
   plausibly introduce here is turning a direct call into a `!hook`
   dereference — a move on paper, an extra indirect call in the interpreter's
   hot path in practice. `bench/run_interp_bench.sh --modes interp` was run
   before and after, and then, because the box was loaded (load average 8–13)
   and single runs varied by >10%, settled with an **interleaved A/B**: base
   and post-extraction `main.exe` copies alternated over 5 rounds with
   `MARCH_STDLIB` pinned.

   | bench | base (median of 4) | after (median of 4) |
   |---|---:|---:|
   | `fib` | 420 ms | 420 ms |
   | `binary_trees` | 361 ms | 368 ms |

   `fib` — the dispatch-bound benchmark, and the one that would move if a hook
   indirection had been introduced — is dead even. `binary_trees` is ~2% slower
   and consistently so (4/4 pairs), which is code-layout, not dispatch: no call
   site changed in either commit, only which compilation unit the definitions
   live in. Isolated non-interleaved runs on this box spanned 410–472 ms for
   `fib` alone, so an absolute-ms comparison would have "found" a 12%
   regression that the A/B shows does not exist.
3. `dune build --root . bin/main.exe` and all six test executables → exit 0.

**Pre-existing red, unrelated:** `dune build --root . @check` exits 1 in this
switch with 17 `Unbound module "Alcotest"` / `Unbound module "March_eval"`
errors under `forge/test/` and `js/`. Verified identical at the base commit by
parking the change and re-running — it is a missing-optional-dependency
condition in the local opam switch, not a consequence of this work.
