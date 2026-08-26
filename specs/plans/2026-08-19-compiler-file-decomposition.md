# Compiler File Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the six largest compiler files searchable, editable, and maintainable by extracting cold bulk into focused modules and converting string-keyed multi-site dispatch into compiler-checked variants.

**Architecture:** Two kinds of change, kept in **separate commits and never mixed**. (1) *Code motion* — definitions move verbatim into new modules; correctness is proven by byte-identical LLVM IR across a 227-program corpus. (2) *Semantic hardening* — string-guard dispatch becomes a variant, parameter floods become records; the IR legitimately changes, so proof is the test suite plus deliberate IR diff review. Phase 0 builds the oracle both kinds rely on; nothing else starts until it is green.

**Tech Stack:** OCaml 5.3.0 (opam switch `march`), dune 3.x, menhir, LLVM textual IR, alcotest.

---

## Target selection revised 2026-08-25 — read with the analysis

**`specs/2026-08-25-file-decomposition-analysis.md` supersedes this plan's choice
of targets and their order.** This plan picked its six files in August from sizes
that were already stale, and ranked them without measuring how often anyone edits
them. The analysis measures three axes — size, concentration (share of the file in
its single largest definition) and **churn** (commits per six months) — and churn
changes the answer materially. Four conclusions bear directly on the phases below:

1. **`typecheck.ml` is the highest-payoff target, not the lowest.** It is the
   largest file in the compiler (14,958 lines) *and* the most edited (387 commits
   in six months, more than `bin/main.ml` or `llvm_emit.ml`). Phase 6 currently
   downscopes it to "cold data only". The downscoping rationale is real — at 10%
   concentration there is no single clean seam, and inference is mutually
   recursive — but that is an argument about technique and sequencing, not value.
   Phase 6 needs a real plan and should not be last.
2. **Concentration without churn is not worth fixing.** `llvm_case.ml` is 95% one
   function, the worst ratio in the tree, and changed 11 times in six months.
   Ranking by concentration promotes cold code; it is the reason `typecheck.ml`'s
   diffuse but expensive bulk was ranked below files nobody edits.
3. **Three actively-edited files are missing from this plan entirely:**
   `lib/tir/lower.ml` (2,001 lines, 134 commits — more churn than
   `refine_check.ml`, which gets a whole phase), `lib/desugar/desugar.ml` (3,321,
   76) and `lib/tir/perceus.ml` (1,998, 66). Each has one dominant function and a
   clear seam. They warrant a phase.
4. **Only 2 of 31 files over 800 lines have an `.mli`.** Adding interface files to
   the highest-churn targets is the cheapest real boundary available — it makes
   accidental coupling a compile error and shrinks the surface a reader must hold,
   without moving a line. Do it *before* the corresponding extraction; it makes
   the extraction safer by declaring what the current surface actually is.

Also worth re-testing: Phase 5 declines to split `bin/main.ml` because "linear
driver code is the friendliest shape to work in". At 337 commits in six months and
a 2,510-line `compile`, that judgement deserves evidence — three separate defects
were found inside that one function during the perf project.

File sizes are no longer recorded in `specs/features/compiler-pipeline.md`; its
status table carried figures stale by 3–7× and now points at the analysis, which
is the single source of truth and carries the commands to re-derive every number.

---

## Re-anchored 2026-08-25 (at `8d2b22fb`, merged onto `origin/main` `7f91ea5d`)

**Read this before executing any task below.** This plan was drafted on 2026-08-19 against
`1f5a0111` and reviewed on 2026-08-23 against `e9adc190`. Between then and now the
interpreter/startup/JIT performance project landed — PRs **#334, #335, #341, #342, #344**
(`perf(eval)` env lookup, `perf(startup)` stdlib typecheck-env cache, in-process ORC JIT
as the REPL backend, `march --jit` for whole programs) — plus PR #343. Those commits moved
code inside the two files this plan cuts up hardest:

- `lib/eval/eval.ml` **12,112 → 12,264** lines. #335 inserted a hashed global-tail lookup
  cache (`install_global_tail`, `assoc_str`, a rewritten `lookup`) at the top of the
  `Evaluation` section — i.e. *below* `base_env`, so every Phase-1 range **above** it is
  untouched but `base_env`'s **end** moved by 117 lines.
- `bin/main.ml` **5,162 → 5,402** lines. `--jit` mode and `get_stdlib_tc_env` shifted the
  second `cas_flags` construction site down by ~175 lines (the first did not move).
- `lib/tir/llvm_emit.ml` **5,255 → 5,719** lines, and `emit_expr`'s body start moved from
  ~1222 to **1348** — so *every* `llvm_emit.ml` line number in Phase 2 is stale by ~126.
- `lib/typecheck/typecheck.ml` **14,908 → 14,957** lines.

Everything in Phases 1-6 that hard-coded a line range has been re-derived against the
current tree, and wherever a stable textual anchor exists the literal number was **replaced
by a `grep`/`awk` derivation** in the style Task 1.3 Step 0 already used. Corrections of
fact are flagged inline with **[corrected 2026-08-25]**. Line numbers that survive
re-measurement are marked **[verified 2026-08-25]** so a later reader can tell "still true"
from "never rechecked".

Two additions in the same pass:

1. **The IR oracle is blind to `lib/eval/eval.ml`.** The interpreter is never emitted as
   LLVM IR, so `scripts/ir-oracle.sh` proves exactly nothing about Phase 1 — the phase that
   dismantles the largest file. Phase 1 therefore gains an **interpreter-performance
   control** (Task 0.3), and its exit gate is stated in Task 1.5.
2. `scripts/ir-oracle.sh` as drafted **did not run** — see Task 0.1 Step 1.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **opam switch is `march`; `dune` and `opam` are already on PATH. NEVER prefix a command with `eval $(opam env …)`.**
- Run tests with `scripts/run-tests.sh`, **not** `dune runtest` (stale RPC daemon silently serves cached results). Judge success by `$?`, never by tail output, and never measure an exit code through a pipe.
- Never pipe `march --compile` — it hangs. Redirect to a file.
- `git add` explicit paths only. Never `git add -A`, `git add .`, `git add *`, or `git commit -am`.
- **Never `git stash` in this worktree** — the stash stack is shared across all march worktrees. Use a file copy to park changes.
- No `Co-Authored-By` trailers.
- **`$SLUG` in the commands below means your worktree's name.** `/tmp` is shared across every march worktree on this box; an unsuffixed scratch path collides with a concurrent agent's, and a torn baseline presents as an inexplicable oracle failure.
- Build with **`dune build --root . <targets>`**. A targetless `dune build --root .` wedges at 0% CPU on this box.
- **`lib/tir/dune` and `lib/refinecheck/dune` carry explicit `(modules …)` lists.** A new module in either directory is *silently not compiled* until it is added to that list. Add it in the same commit that creates the file. `lib/typecheck`, `lib/eval` (`(:standard \ discover_compress)`), and `lsp/lib` use default discovery — nothing to edit there.
- Before trusting any "pre-existing failure", rebuild fully: a targeted `dune build --root . bin/main.exe` does **not** refresh `_build`'s staged copies of `stdlib/` and `runtime/`, which manufactures fake failures.
- Per CLAUDE.md: when a task closes a `specs/todos/` item, `git mv` it to `specs/progress/` in the same commit. Pure-refactor commits with no user-visible behavior change do **not** get a `CHANGELOG.md` bullet; Phase 2 and Phase 3 hardening *do* (they change diagnostics/codegen structure).

---

## Measured Baseline

**[corrected 2026-08-25]** — re-measured at `8d2b22fb`. The `1f5a0111` column is kept so the
drift is visible; the `8d2b22fb` column is what the tasks below are anchored to.

| File | Lines @`1f5a0111` | Lines @`8d2b22fb` | Largest single def @`8d2b22fb` | % of file | § headers | `.mli` |
|---|---|---|---|---|---|---|
| `lib/tir/llvm_emit.ml` | 5,255 | **5,719** | `emit_expr` **4,319** (`:1348–5666`) | **76%** | 0 | no |
| `bin/main.ml` | 5,162 | **5,402** | `compile` **2,510** (`:2298–4807`) | 46% | 10 | no |
| `lib/eval/eval.ml` | 12,112 | **12,264** | `base_env` **5,274** (`:4235–9508`) | 43% | 70 | no |
| `lsp/lib/analysis.ml` | 8,132 | 8,132 *(unchanged)* | 3 fns ≈3,000 | 37% | 49 | no |
| `lib/desugar/desugar.ml` | 3,320 | 3,320 *(unchanged)* | `derive_impl` 942 | 28% | 8 | no |
| `lib/refinecheck/refine_check.ml` | 7,416 | 7,416 *(unchanged)* | `check_call` **1,361** (`:3371–4731`) | 18% | **0** | no |
| `lib/typecheck/typecheck.ml` | 14,908 | **14,957** | `infer_expr` **1,500** (`:5724–7223`) | **10%** | 21 | no |

Regenerate this table with:

```bash
wc -l lib/tir/llvm_emit.ml bin/main.ml lib/eval/eval.ml lsp/lib/analysis.ml \
      lib/desugar/desugar.ml lib/refinecheck/refine_check.ml lib/typecheck/typecheck.ml
```

**`typecheck.ml` is the best-decomposed file of the set** — longest, but most evenly divided. It is therefore *last* in this plan, not first. Length is not the problem; a 4,000-line single function is.

**Correction to an earlier hypothesis:** `analysis.ml`'s two ~1,000-line code-action functions were suspected duplicates. They are not. `ast_code_actions` is called exactly once, at `analysis.ml:7755`, appended to `code_actions_at`'s result, and their action-title sets do not intersect. They are complementary (diagnostic-driven vs AST-driven). Phase 4 is therefore a plain split, not a dedup.

---

## The Verification Oracle

`--emit-llvm` writes `<file>.ll` and exits **before** the CAS cache path, so it cannot be short-circuited by a warm cache. **[verified 2026-08-25]** — the claim was re-checked structurally *and* empirically, not taken on faith:

- *Structurally:* in `bin/main.ml`'s `compile`, the CAS `lookup_artifact` call sits inside the `if !do_compile then begin … end` branch (`main.ml:3792` at `8d2b22fb`); the `--emit-llvm`-only write (`open_out ll_file`, `main.ml:4585`) is in that branch's `else`. The two paths never meet.
- *Empirically:* compiling a probe twice until the second run printed `compiled … (cached)`, then running `--emit-llvm` on the same source, still wrote the `.ll`. Two differently-named copies of that source produced **identical** sha256 — no path, timestamp, or UUID is baked in.

**Hash the `.ll` text, never the binaries.** `cmp` of two freshly linked Mach-O binaries is vacuous on macOS: `LC_UUID` is random per link, so they always differ.

This makes IR hashing a sound oracle for code motion. It is the linchpin of the plan: a task that claims "I only moved code" must *prove* it, because this repo has a documented history of vacuous-green results (stale `_build` staging, warm-CAS short-circuit, skip-on-compile-failure).

Corpus **[corrected 2026-08-25]**: **181** `test/native/*.march` (was 165) + 16 `test/snapshots/src/*.march` + 46 `bench/*.march` = **243 programs**, of which **240 emit IR** and **3 skip** (`bench/http_get*.march` — they need a live server). The script's `emitted < 100` guard is what makes a shrunken corpus loud rather than silent; do not tighten it to an equality against 240, because the corpus grows.

**The oracle is blind to `lib/eval/eval.ml`.** The interpreter is never lowered to LLVM IR, so a Phase-1 extraction that mangles the interpreter emits byte-identical IR and the oracle stays green. Phase 1's proof is the eval/stdlib suites **plus** the interpreter-performance control in Task 0.3 — not this oracle.

---

## File Structure

New files created by this plan. Each has one responsibility; files that change together live together.

| New file | Responsibility | Extracted from | Approx. lines |
|---|---|---|---|
| `scripts/ir-oracle.sh` | Hash LLVM IR for the 227-program corpus; compare against a saved baseline | — | ~70 |
| `lib/eval/eval_types.ml` | Interpreter `value` / `env` type block (PREREQUISITE for all of Phase 1) | `eval.ml:17-142` **[verified 2026-08-25]** | ~126 |
| `lib/eval/eval_prim.ml` | `Eval_error` + `eval_error` + late-bound hook refs — the bottom layer that breaks the extraction cycle | `eval.ml:894/:1096/:1239/:1520/:1814-1824` **[verified 2026-08-25;** `:894` **is `http_fetch_hook`, omitted from the draft's list]** | ~40 |
| `lib/eval/eval_runtime.ml` | Shared runtime state: actor registry, scheduler entry, type tables, timers, vault registry | `eval.ml` (scattered; Task 1.3 Step 0 derives it) | ~450 |
| `lib/eval/eval_simd.ml` | Simd 128-bit vector ops + NativeArray narrow-width (f32/i32/u8) helpers | `eval.ml:4054–4205` **[corrected 2026-08-25;** was `4054–4206`, one line into the next header**]** | ~150 |
| `lib/eval/eval_net.ml` | CSV parser, HTTP server, WebSocket, non-blocking connection multiplexer | `eval.ml:2691–3861` **[verified 2026-08-25]** | ~1,170 |
| `lib/eval/eval_session.ml` | Session-typed channel runtime + MPST runtime | `eval.ml:3862–3987` **[verified 2026-08-25]** | ~125 |
| `lib/eval/eval_builtins.ml` | `base_env` (**595** entries) plus its ~85 table-exclusive helpers | `eval.ml:4207–9510` **[corrected 2026-08-25;** was `4207–9393`**]** + scattered | ~5,400 |
| `lib/eval/eval_builtins.mli` | Interface: `val base_env : Eval_types.env` | — | ~5 |
| `lib/tir/builtin_name.ml` | `Builtin_name.t` variant + `of_string`/`to_string` for the **57** codegen-dispatched builtins **[corrected 2026-08-25;** was 50, then 58**]** | — | ~140 |
| `lib/tir/builtin_name.mli` | Interface | — | ~15 |
| `lib/tir/llvm_emit_arith.ml` | Int/float arithmetic, comparison, bitwise arms | `llvm_emit.ml` | ~700 |
| `lib/tir/llvm_emit_task.ml` | task_*, actor, signal, channel, MPST arms | `llvm_emit.ml` | ~900 |
| `lib/tir/llvm_emit_record.ml` | record_*, vault_*, html_*, to_string arms | `llvm_emit.ml` | ~800 |
| `lib/refinecheck/refine_check.mli` | Public API of the refinement checker | — | ~40 |
| `lib/typecheck/builtin_caps.ml` | `builtin_cap_table` — 115-line pure string-pair list | `typecheck.ml:1967` **[corrected 2026-08-25;** was `~1025`**]** | ~145 |
| `lsp/lib/code_actions_ast.ml` | AST-driven refactorings (pipe, extract, …) | `analysis.ml:5675–6763` **[verified 2026-08-25]** | ~1,090 |
| `lsp/lib/code_actions_diag.ml` | Diagnostic-driven quick fixes | `analysis.ml:6764–7760` **[verified 2026-08-25]** | ~1,000 |

Files **not** touched: `lib/desugar/desugar.ml` (3,320 lines, 8 sections, largest def is a 942-line template-expander — healthy), `lsp/test/test_lsp.ml` (7,145 lines but 395 independent top-level tests and 177 headers — test files are the benign case).

**Precedent:** `test/test_ir_verify.ml`'s header comment already establishes this repo's convention — it was created as "a NEW file rather than growing test_codegen.ml (already ~6400 lines)". This plan applies that same judgment to `lib/`.

---

## Phase 0 — Build the oracle

Nothing else in this plan may start until Task 0.1 is committed and green. Every subsequent code-motion task depends on it.

### Task 0.1: IR hashing harness — **DONE 2026-08-25** (`scripts/ir-oracle.sh` is committed)

**Files:**
- Create: `scripts/ir-oracle.sh` ✅
- Create: `specs/todos/2026-08-19-compiler-file-decomposition.md` (tracking item for the whole plan) ✅

**Interfaces:**
- Produces: `scripts/ir-oracle.sh baseline <dir>` writes one `.sha256` manifest; `scripts/ir-oracle.sh check <dir>` diffs current IR against it and exits non-zero on any mismatch. Every later task calls exactly these two subcommands.

- [x] **Step 1: Write the script**

The script now lives in the repo — **read `scripts/ir-oracle.sh`, do not re-type the draft that used to sit inline here.** It was inlined in the 2026-08-19 draft and that draft **did not run**:

```bash
MODE="${1:?usage: ir-oracle.sh {baseline|check} <dir>}"   # BROKEN
```

Bash ends a `${x:?word}` expansion at the **first** `}`, so the `}` in `{baseline|check}` closed it early and the literal tail ` <dir>}` was concatenated onto the value. `MODE` came out as `baseline <dir>}` and every invocation died with `unknown mode`. The committed script keeps the usage text in a `}`-free variable. **[corrected 2026-08-25]**

The committed version also `rm -f`s a stale `$WORK/$tag.ll` before each run, so a fixture that newly fails to compile cannot be scored against the previous run's leftover `.ll`.

- [x] **Step 2: Make it executable and record the baseline**

```bash
chmod +x scripts/ir-oracle.sh
dune build --root . bin/main.exe
scripts/ir-oracle.sh baseline /tmp/ir-base-<slug>
```

Measured at `8d2b22fb`: `emitted=240 skipped=3`, exit 0. **[corrected 2026-08-25]** — the draft expected ~227 programs; the corpus is now 243 files (181 + 16 + 46). The 3 skips are `bench_http_get`, `bench_http_get_close`, `bench_http_get_keepalive`, which need a live server. If it prints `FATAL: only N fixtures emitted`, stop — the build is stale or the exe is wrong.

Suffix `<slug>` with your worktree name. `/tmp` is shared across every march worktree on this box and a bare `/tmp/ir-base` will collide with a concurrent agent's baseline — which presents as an inexplicable IR diff, i.e. exactly the failure this oracle is supposed to make trustworthy.

- [x] **Step 3: Prove the oracle DETECTS a change (the critical step)**

An oracle that never fires is worthless. **Executed 2026-08-25 at `8d2b22fb`:**

*GREEN control* — a comment-only edit above `int_arith_op` in `lib/tir/llvm_emit.ml`, rebuilt: `IR IDENTICAL across 240 programs`, exit 0.

*RED probe* — a one-token semantic change in the same function:

```ocaml
let int_arith_op = function
  | "+" -> "add nsw" | "-" -> "sub" | "*" -> "mul"    (* was: "add" *)
```

```bash
dune build --root . bin/main.exe && scripts/ir-oracle.sh check /tmp/ir-base-<slug>; echo "exit=$?"
```

Result: `IR CHANGED — 262 differing lines`, exit 1 — **131 of 240** programs changed hash. Pick a probe with broad reach like this one; the draft suggested editing the `int_max_value` constant, but only two corpus fixtures use it, so a green there would have been nearly indistinguishable from a broken oracle. **[corrected 2026-08-25]**

- [x] **Step 4: Revert the probe and confirm green**

```bash
git checkout -- lib/tir/llvm_emit.ml && dune build --root . bin/main.exe
scripts/ir-oracle.sh check /tmp/ir-base-<slug>; echo "exit=$?"
```

Result: `IR IDENTICAL across 240 programs`, exit 0.

- [x] **Step 5: Record the tracking todo**

Create `specs/todos/2026-08-19-compiler-file-decomposition.md` (see the file for current status).

- [x] **Step 6: Commit**

```bash
git add scripts/ir-oracle.sh specs/plans/2026-08-19-compiler-file-decomposition.md specs/todos/2026-08-19-compiler-file-decomposition.md && git commit -m "test: add LLVM IR oracle for behavior-preserving refactors"
```

### Task 0.2: Record the full-suite baseline — **DONE 2026-08-25**

**Files:** none modified — this task produces a recorded artifact only.

- [x] **Step 1: Run the full suite and save the result**

```bash
scripts/run-tests.sh > /tmp/suite-base-<slug>.log 2>&1; echo "exit=$?"; tail -20 /tmp/suite-base-<slug>.log
```

- [x] **Step 2: Record the pass/fail counts**

Recorded at `8d2b22fb`, **exit 0, zero failures**:

| suite | tests run |
|---|---:|
| `run_compiler` | 936 |
| `run_eval` | 273 |
| `run_codegen` | 591 |
| `run_stdlib` | 878 |
| `test_stdlib_march` | 61 |
| `test_jit` | 20 |
| **total** | **2,759** |

`test_jit` joined `scripts/run-tests.sh` in #347, which merged into this branch after the
first baseline run; its 20 tests were measured separately (exit 0). Note the runner's own
warning: invoked outside `dune runtest`, `test_jit.ml` **silently skips** unless `HOME` and
`MARCH_BIN` are pinned — `scripts/run-tests.sh` pins them, a bare
`./_build/default/test/test_jit.exe` does not. A "20 passed" from the wrong invocation is
the vacuous kind.

**There are no pre-existing failures to carry.** Any failure a later task sees is that task's own — this baseline removes the usual "it was already broken" escape hatch. Wall time ~11 min on a loaded box (the plan's `~17s` in CLAUDE.md is an unloaded number).

Operational note for this box: it is shared, and other sessions have killed test processes mid-run. If a runner dies with no summary (exit 143/144, truncated output), that is not a failure — copy the exe within `_build/default/test/` under a different name, rerun it from the same directory, and say so in the report.

- [x] **Step 3: Record the TIR snapshot baseline**

```bash
dune build --root . test/run_snapshots.exe && ./_build/default/test/run_snapshots.exe -e > /tmp/snap-base-<slug>.log 2>&1; echo "exit=$?"
```

Result at `8d2b22fb`: exit 0, **33 tests run**. TIR snapshots pin lowering/Perceus shape; the IR oracle pins final codegen. Phases 1 and 6 must leave **both** untouched.

### Task 0.3: Record the interpreter-performance baseline — **ADDED and DONE 2026-08-25**

**Why this exists.** The IR oracle cannot see `lib/eval/eval.ml` at all — the interpreter is never emitted as LLVM IR. Phase 1 is the phase that dismantles that exact file, so Phase 1 is the one phase whose central proof artifact does not apply to it. The suites prove the interpreter still computes the right answers; nothing yet proves it still computes them at the same speed.

**The plausible failure this catches.** Phase 1 routes `Eval_builtins`/`Eval_net`/`Eval_session` back into the evaluator through `Eval_prim`'s hook `ref`s (Task 1.0b). That indirection already exists at four sites today. An extraction that is careless about which calls are *already* hooks will convert a **direct** call into a `!hook` dereference — a code move on paper, an extra indirect call in the interpreter's hot path in practice. The env-lookup work in #335 bought ~11x on interpreted runs; silently giving part of it back to a refactor would be a bad trade made invisibly.

**Files:** none modified except the appended benchmark record.

- [x] **Step 1: Record the baseline**

```bash
bash bench/run_interp_bench.sh --modes interp --runs 3 --tag decomp-baseline-$(git rev-parse --short HEAD)
```

Recorded at `8d2b22fb` (tag `decomp-baseline-8d2b22fb`, appended to `bench/results/2026-08-25-interp-arm64.jsonl` — that directory is committed on purpose; see `.gitignore`'s `!/bench/results/`). Interpreted min/median ms:

| bench | min / median |
|---|---:|
| actor_call_storm | 1913 / 1914 |
| actor_pingpong | 374 / 376 |
| binary_trees | 352 / 352 |
| fib | 406 / 417 |
| float_loop | 695 / 696 |
| http_server | 244 / 253 |
| json_stream | 10221 / 10234 |
| par_fib | 416 / 418 |
| par_map | 1668 / 1674 |
| string_pipeline | 390 / 400 |
| string_split | 946 / 947 |

- [ ] **Step 2: Re-run it as Phase 1's exit gate — see Task 1.5**

---

## Phase 1 — `eval.ml`: 12,264 → ~5,000 lines — **LANDED 2026-08-25**

**[corrected 2026-08-25]** — the header used to read `12,112 → ~4,900`.

**Done.** `eval.ml` is **4,304 lines** (target ~5,000). Tasks 1.0/1.0b landed in
#353; Tasks 1.1–1.5 landed on `claude/eval-decomp-phase1-finish`. See
`specs/progress/2026-08-25-eval-decomposition-phase1.md` for what each task
actually moved, where the plan's shape had to be adjusted, and the exit-gate
numbers. Two deviations worth knowing before reading the tasks below:

- Extractions are re-exported from `eval.ml` with **`include`**, not `open` —
  the test suite reaches these names through `let open March_eval.Eval in`, so
  `open Eval_simd` compiles `eval.ml` but breaks `test/test_stdlib_suite.ml`.
- Task 1.3's "table-exclusive helpers stay inside `eval_builtins.ml`" split was
  **not** used. The table's dependency closure inside `eval.ml` is 75
  definitions that reference each other; splitting them across two new modules
  buys hiding at the cost of a fragile shared/exclusive judgement the build can
  only arbitrate one error at a time. All 75 went to `eval_runtime.ml`, and
  `eval_builtins.mli` still exports `base_env` and nothing else.

Task 1.5 Step 3 (committing the `bench/results/*.jsonl` record) was
deliberately **not** done — the exit-gate A/B was run as a direct interleaved
comparison of two `main.exe` copies, not through `bench/run_interp_bench.sh`,
so there is no JSONL row to append. The numbers are in the progress note.

Highest ROI and lowest risk. `base_env` (**5,274** lines, **595** entries — was 5,187/590) references `eval_expr`/`eval_decl` **zero times** — the dependency runs strictly one way. The cycle-breaking machinery already exists in the file: `http_fetch_hook` (:894), `iface_dispatch_hook` (:1520), `eval_expr_hook` (:1814), `run_scheduler_hook` (:1819), `apply_hook` (:1824) — **all five [verified 2026-08-25]**, because #335's insertion landed *below* `base_env` and shifted nothing above it. Extraction reuses that established pattern rather than inventing one.

**The IR oracle proves nothing here.** See Task 0.3. Phase 1's gate is the suites plus the interpreter-performance control in Task 1.5; run the oracle anyway (a Phase-1 commit that changes IR means something outside `lib/eval` moved), but never treat its green as evidence the interpreter is intact.

**Ordering matters, and the invariant is directional:** every extraction leaves `eval.ml` depending on the new module, so extracted code may reference **nothing that remains in `eval.ml`** — not merely nothing below its own block. Tasks 1.0/1.0b lay the bottom layer (types, then errors + hooks); Tasks 1.1–1.2 extract the leaf helper clusters; Task 1.3 splits the shared runtime state from the builtin table and moves both.

### Task 1.0: Extract the value/env type block (PREREQUISITE)

**Verified prerequisite, not a hedge — re-verified 2026-08-25:** `Eval_types` still does **not** exist (`lib/eval/` contains exactly one module, `eval.ml`). `type value` is at `eval.ml:32` and `and env` at `eval.ml:141`, both inside `eval.ml`. Every later task in Phase 1 needs these types from a sibling module, so this task must land first.

The block is lines **17-142** (`Ring buffer type` through `and env`) and contains *only* type definitions — no `let` bindings — so it moves cleanly. **[verified 2026-08-25]** Derive the bounds rather than trusting the literals:

```bash
S=$(grep -n 'Ring buffer type' lib/eval/eval.ml | head -1 | cut -d: -f1); S=$((S-1))
E=$(grep -n '^and env = ' lib/eval/eval.ml | cut -d: -f1); E=$((E+1))
echo "block = $S..$E"      # 17..142 at 8d2b22fb
```

**Files:**
- Create: `lib/eval/eval_types.ml`
- Modify: `lib/eval/eval.ml`

**Interfaces:**
- Produces: `type value`, `and env = (string * value) list`, plus the mutually-recursive record types `chan_endpoint` (:85), `mpst_endpoint` (:99), `timer_entry` (:117) and the ring-buffer type at :17. All keep their current names and shapes verbatim.

- [x] **Step 1: Confirm the block contains no value bindings**

```bash
awk 'NR>=17 && NR<=142' lib/eval/eval.ml | grep -nE '^\s*let '
```

Expected: **no output**. Any hit means a function is interleaved with the types and must stay behind.

- [x] **Step 2: Move lines 17-142 verbatim**

```bash
{ echo '(** Interpreter value and environment types.'
  echo
  echo '    Extracted verbatim from eval.ml:17-142 so that the builtin table,'
  echo '    the protocol runtimes, and the evaluator can live in sibling modules'
  echo '    without a dependency cycle.  No behavior change. *)'
  echo
  sed -n '17,142p' lib/eval/eval.ml
} > lib/eval/eval_types.ml
sed -i.bak '17,142d' lib/eval/eval.ml && rm lib/eval/eval.ml.bak
```

- [x] **Step 3: Re-export the types from `eval.ml`**

`Eval.value` and `Eval.env` are referenced across the compiler and test suite. Add at the top of `eval.ml`, where the block used to be:

```ocaml
(* Value and environment types moved to eval_types.ml.  Re-exported so
   [Eval.value] / [Eval.env] keep working for existing call sites. *)
include Eval_types
```

`include` (not `open`) is required — `open` would make the constructors visible inside `eval.ml` but would NOT re-export them to `Eval.*` consumers.

- [x] **Step 4: Build and verify**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "ir_exit=$?"
scripts/run-tests.sh eval; echo "suite_exit=$?"
```

Expected: both exit 0. `include` changes no runtime behavior, so IR must be identical.

- [x] **Step 5: Commit**

```bash
git add lib/eval/eval_types.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract value and env types to eval_types.ml"
```

### Task 1.0b: Extract `eval_prim.ml` — the error/hook layer (PREREQUISITE)

**Added at review (2026-08-23):** every extraction block in this phase references names that would otherwise stay in `eval.ml` — `eval_error` (base_env ×717, session ×10, net ×4, simd ×1) and the hook refs (base_env ×41, net ×4). Because `eval.ml` will depend on the extracted modules, any such reference is a **module cycle — a hard compile error**. This task moves that shared bottom layer beneath everything else, so the later extractions have somewhere legal to point.

**Files:**
- Create: `lib/eval/eval_prim.ml`
- Modify: `lib/eval/eval.ml`

**Interfaces:**
- Consumes: `Eval_types` (Task 1.0).
- Produces: `exception Eval_error of string`; `val eval_error : ('a, unit, string, 'b) format4 -> 'a`; and every hook ref — `iface_dispatch_hook`, `eval_expr_hook`, `run_scheduler_hook`, `apply_hook`, `http_fetch_hook` — each with its current type and placeholder initializer verbatim.

- [x] **Step 1: Enumerate what must move — do not trust the list above**

```bash
grep -nE '^let [a-z_]*_hook\b' lib/eval/eval.ml
grep -n '^exception Eval_error\|^let eval_error' lib/eval/eval.ml
```

Expected at `1f5a0111`: `iface_dispatch_hook` :1520, `eval_expr_hook` :1814, `run_scheduler_hook` :1819, `apply_hook` :1824, plus `http_fetch_hook`; `exception Eval_error` :1096; `let eval_error` :1239. Move **every** hook the first grep prints, not just the named ones.

Also enumerate any *other* exception the extraction blocks raise, so it moves too:

```bash
awk 'NR>=2691 && NR<9394' lib/eval/eval.ml | grep -oE 'raise \(?[A-Z][A-Za-z_]*' | sort | uniq -c | sort -rn
```

Any exception in that output that is defined in `eval.ml` joins `Eval_error` in `eval_prim.ml`.

- [x] **Step 2: Write `eval_prim.ml`**

Move the definitions by name (they are one-liners scattered across sections — not a contiguous range). The file should read:

```ocaml
(** Bottom layer of the interpreter: the evaluation-error exception and the
    late-bound hook refs through which extracted modules re-enter the
    evaluator.

    Everything in lib/eval may depend on this module; it depends on nothing
    in lib/eval except [Eval_types].  That is the whole point — without it,
    [Eval_builtins]/[Eval_net]/[Eval_session] would need [Eval.eval_error]
    while [Eval] needs their exports: a cycle.

    The hook refs keep their placeholder initializers; [Eval] installs the
    real functions at startup exactly as before. *)

open March_ast.Ast
open Eval_types

exception Eval_error of string

let eval_error fmt = Printf.ksprintf (fun s -> raise (Eval_error s)) fmt

(* Hook refs — copied verbatim from eval.ml, including their placeholder
   bodies and the comments explaining who installs them. *)
```

followed by the hook definitions copied verbatim from the lines Step 1 printed. Then delete those definitions from `eval.ml`.

- [x] **Step 3: Re-export from `eval.ml` at the original positions**

`Eval.Eval_error` may be matched externally and the hooks are installed by `eval.ml` itself, so keep every name resolvable under `Eval.`:

```ocaml
exception Eval_error = Eval_prim.Eval_error
let eval_error = Eval_prim.eval_error
let iface_dispatch_hook = Eval_prim.iface_dispatch_hook
let eval_expr_hook = Eval_prim.eval_expr_hook
let run_scheduler_hook = Eval_prim.run_scheduler_hook
let apply_hook = Eval_prim.apply_hook
let http_fetch_hook = Eval_prim.http_fetch_hook
```

Aliasing a `ref` is safe — alias and original are the same mutable cell, so the startup installation (`eval_expr_hook := …`) in `eval.ml` keeps working unchanged.

- [x] **Step 4: Build, verify IR, run the eval suite**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "ir_exit=$?"
scripts/run-tests.sh eval; echo "suite_exit=$?"
```

Expected: both exit 0.

- [x] **Step 5: Commit**

```bash
git add lib/eval/eval_prim.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract Eval_error and hook refs to eval_prim.ml"
```

### Task 1.1: Extract Simd + NativeArray narrow-width helpers

**Files:**
- Create: `lib/eval/eval_simd.ml`
- Modify: `lib/eval/eval.ml:4054–4205` (delete after moving — derive the bounds in Step 1)
- Test: `scripts/ir-oracle.sh` + `scripts/run-tests.sh eval`

**Interfaces:**
- Consumes: `Eval_types.value` (already a separate concern in `eval.ml`'s §Value type at :29 — if it is not yet its own module, keep the type in `eval.ml` and have `eval_simd.ml` take it as a functor-free direct dependency by placing `eval_simd.ml` *after* the value type; see Step 2).
- Produces: `simd_all`, `simd_any`, `simd_bounds_check`, `simd_first_set`, `simd_hfold`, `simd_select`, `simd_maxnum_f`, `simd_minnum_f`, `simd_f32_{and,or,xor,not,zero,allones,is_highbit}`, `simd_f64_{and,or,xor,not,zero,allones,is_highbit}`, `simd_i32_is_highbit`, `simd_i64_is_highbit`, `simd_u8_is_highbit`, `f32_round`, `fma32_single_round`, `i32_wrap`, `u8_wrap`. All keep their current signatures verbatim.

- [x] **Step 1: Confirm the exact boundary before touching anything**

Derive the bounds; do not paste the literals. **[verified 2026-08-25 — these anchors still resolve to 4054 / 4117 / 4207, unchanged since `1f5a0111`, because #335's insertion landed below `base_env`.]**

```bash
S=$(grep -n 'NativeArray narrow-width helpers' lib/eval/eval.ml | cut -d: -f1)
E=$(grep -n 'Base environment' lib/eval/eval.ml | cut -d: -f1); E=$((E-2))
echo "simd block = $S..$E"          # 4054..4205 at 8d2b22fb
sed -n "${S},$((S+4))p;$((E-1)),$((E+3))p" lib/eval/eval.ml
```

Expected: `$S` opens the `NativeArray narrow-width helpers` comment, the `Simd` header sits inside the block (4117), and `$E+1` is the `(* ---- *)` rule that belongs to the `Base environment` header at `$E+2`. The block to move is **`$S`–`$E` inclusive**.

**[corrected 2026-08-25]** — the draft said `4054–4206`, one line too many: 4206 is the *opening* rule of the `Base environment` header, so moving it would leave that header with no top rule and put a stray rule at the bottom of `eval_simd.ml`. The correct end is **4205** (the blank line before that rule). Use the derivation above and this class of off-by-one cannot recur.

- [x] **Step 2: Check the block's upward dependencies**

```bash
sed -n "${S},${E}p" lib/eval/eval.ml | grep -oE '\b[a-z_][a-z0-9_]{3,}\b' | sort -u > /tmp/simd-ids-$SLUG.txt
grep -oE '^let ([a-z_][a-z0-9_]*)' lib/eval/eval.ml | sed 's/^let //' | sort -u > /tmp/eval-defs-$SLUG.txt
comm -12 /tmp/simd-ids-$SLUG.txt /tmp/eval-defs-$SLUG.txt
```

(`$S`/`$E` from Step 1. `$SLUG` is your worktree name — `/tmp` is shared across march worktrees and unsuffixed scratch names collide with concurrent agents.)

The direction that matters: `eval.ml` will depend on `eval_simd`, so the block may reference **nothing that remains in `eval.ml`** — whether it is defined above or below the block is irrelevant. Every name the `comm` prints must resolve to `Eval_types` (Task 1.0) or `Eval_prim` (Task 1.0b). Measured at review: the block's only `eval.ml` dependency is `eval_error` ×1, which Task 1.0b already moved. If other names appear, they move with the block or the block stays — stop and report.

- [x] **Step 3: Move the block verbatim**

```bash
{ echo '(** Simd 128-bit vector ops and NativeArray narrow-width (f32/i32/u8)'
  echo "    helpers.  Extracted verbatim from eval.ml:${S}-${E} — no behavior"
  echo '    change.  See specs/plans/2026-08-19-compiler-file-decomposition.md *)'
  echo
  echo 'open Eval_types'
  echo
  sed -n "${S},${E}p" lib/eval/eval.ml
} > lib/eval/eval_simd.ml
sed -i.bak "${S},${E}d" lib/eval/eval.ml && rm lib/eval/eval.ml.bak
```

- [x] **Step 4: Re-point the use sites**

`base_env` calls these unqualified. Add at the top of `eval.ml`, immediately after its existing `open` lines:

```ocaml
open Eval_simd
```

`open Eval_types` resolves because Task 1.0 created that module. If it does not compile, Task 1.0 was skipped — go back and land it first rather than working around it here.

- [x] **Step 5: Build and verify IR is untouched**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "exit=$?"
```

Expected: `IR IDENTICAL across N programs`, `exit=0`, with N matching the baseline exactly.

- [x] **Step 6: Run the eval suite**

```bash
scripts/run-tests.sh eval; echo "exit=$?"
```

Expected: exit 0, same counts as `/tmp/suite-base-$SLUG.log`.

- [x] **Step 7: Commit**

```bash
git add lib/eval/eval_simd.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract Simd and NativeArray narrow-width helpers"
```

### Task 1.2: Extract the network/protocol runtime cluster

**Files:**
- Create: `lib/eval/eval_net.ml` (CSV, HTTP server, WebSocket, non-blocking multiplexer — `eval.ml:2691–3861` **[verified 2026-08-25]**)
- Create: `lib/eval/eval_session.ml` (session channels + MPST — `eval.ml:3862–3987` **[verified 2026-08-25]**)
- Modify: `lib/eval/eval.ml`

Derive both, in this order (session first, so net's numbers are still pre-shift):

```bash
NS=$(grep -n 'CSV parser state' lib/eval/eval.ml | cut -d: -f1); NS=$((NS-1))
SS=$(grep -n 'Session-typed channel runtime' lib/eval/eval.ml | cut -d: -f1); SS=$((SS-1))
SE=$(grep -n 'Show dispatch helper' lib/eval/eval.ml | cut -d: -f1); SE=$((SE-2))
echo "net = $NS..$((SS-1))   session = $SS..$SE"   # 2690..3860  3861..3986 at 8d2b22fb
```

**[corrected 2026-08-25]** — the literals `2691–3861` / `3862–3987` name the *title* lines, not the `(* ---- *)` rules that open and close each header. The derivation above takes the rules with their sections, which is what you want; the one-line discrepancy is why it is worth deriving rather than pasting.

**Interfaces:**
- Produces from `eval_net.ml`: `csv_open_impl`, `csv_next_row_impl`, `csv_close_impl`, `handle_http_connection`, `run_http_event_loop`, `tcp_send_all`, `ws_send_frame`, `ws_recv_frame`.
- Produces from `eval_session.ml`: `chan_new`, `chan_send`, `chan_recv`, `chan_close`, `mpst_new`, `mpst_send`, `mpst_recv`, `mpst_close`.

- [x] **Step 1: Verify both blocks are leaves**

Run the Step-2 dependency check from Task 1.1 against ranges `$NS,$((SS-1))` and `$SS,$SE`. Same rule as Task 1.1: every dependency must resolve to `Eval_types`, `Eval_prim`, or `Eval_simd` — nothing may remain in `eval.ml`. Measured at review: net uses `eval_error` ×4 and hook refs ×4; session uses `eval_error` ×10 — all satisfied by `Eval_prim`.

Mind the reverse direction too: a helper defined *inside* these blocks that the rest of `eval.ml` still uses (e.g. `tcp_send_all`) must be re-exported (`let tcp_send_all = Eval_net.tcp_send_all`) or have its remaining uses qualified. The build names every such case — fix them, don't work around them.

Note the ordering constraint recorded in the file at `eval.ml:3496` **[verified 2026-08-25]**: `handle_http_connection` is the blocking implementation and the non-blocking multiplexer below it references it. Keep both in `eval_net.ml`, in their current relative order.

- [x] **Step 2: Move `eval_session.ml` first (the smaller, cleaner block)**

```bash
{ echo '(** Session-typed channel runtime and multi-party (MPST) runtime.'
  echo "    Extracted verbatim from eval.ml:${SS}-${SE} — no behavior change. *)"
  echo
  sed -n "${SS},${SE}p" lib/eval/eval.ml
} > lib/eval/eval_session.ml
sed -i.bak "${SS},${SE}d" lib/eval/eval.ml && rm lib/eval/eval.ml.bak
dune build --root . bin/main.exe 2>&1 | tail -5
```

- [x] **Step 3: Verify, then commit separately**

```bash
scripts/ir-oracle.sh check /tmp/ir-base-$SLUG && scripts/run-tests.sh eval; echo "exit=$?"
git add lib/eval/eval_session.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract session-typed and MPST channel runtimes"
```

- [x] **Step 4: Move `eval_net.ml`**

Line numbers have shifted by the Step-2 deletion. Re-locate before cutting:

```bash
grep -n 'CSV parser state\|Session-typed channel runtime' lib/eval/eval.ml
```

Use the CSV line as the new start and the line before the session marker (now the `Show dispatch helper` section) as the end. Move that range with the same pattern as Step 2.

- [x] **Step 5: Verify and commit**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG && scripts/run-tests.sh eval; echo "exit=$?"
git add lib/eval/eval_net.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract CSV, HTTP, and WebSocket interpreter runtimes"
```

### Task 1.3: Extract `base_env` — the 5,274-line builtin table

**[corrected 2026-08-25]** — was "5,187-line". `base_env` is `eval.ml:4235–9508` at `8d2b22fb`; its **end** moved (+117 lines) while its start did not, so every literal end-of-table number in the 2026-08-19 draft is wrong and every start number is right. This task already derives both with `grep`, which is why it needed the least repair in the plan — **follow this task's style everywhere else.**

**Do not sweep up the new lookup cache.** Immediately below the `(* Evaluation *)` rule that terminates this task's range sit `install_global_tail`, `assoc_str` and the rewritten `lookup` (`eval.ml:9528/:9540/:9547`), added by #335 for an ~11x interpreted speedup. They are evaluator, not builtin table; they stay in `eval.ml`. The `E=$(grep -n '(\* Evaluation' …)` bound below already excludes them — do not "tidy" it into a larger range.

**Rewritten at review (2026-08-23):** the first draft assumed the table's ~120 helper dependencies could stay in `eval.ml`. They cannot — `eval.ml` will depend on `eval_builtins.ml`, so anything the table uses must live in a sibling module. This task is therefore **two extractions**: first the *shared* runtime-state cluster (used by both the table and the evaluator) into `eval_runtime.ml`; then the table plus its *table-exclusive* helpers into `eval_builtins.ml`.

**Files:**
- Create: `lib/eval/eval_runtime.ml`, `lib/eval/eval_builtins.ml`, `lib/eval/eval_builtins.mli`
- Modify: `lib/eval/eval.ml`

**Interfaces:**
- Consumes: `Eval_types`, `Eval_prim`, `Eval_simd`, `Eval_net`, `Eval_session`.
- Produces from `eval_runtime.ml`: the shared runtime state. Measured at review (27 names, regenerate in Step 0 — it drifts): `actor_registry`, `impl_tbl`, `run_scheduler`, `ctor_type_tbl`, `type_name_of_value`, `next_pid`, `current_pid`, `named_registry`, `ffi_type_decl_tbl`, `shutdown_requested`, `record_type_tbl`, `pending_timers`, `vault_num_stripes`, `vault_registry`, `spawn_child_actor`, `timer_service_tick`, `dropped_messages_count`, `mailbox_enqueue`, `base64_decode`, `revocation_table`, `protocol_roles_tbl`, `logger_level`.
- Produces from `eval_builtins.ml`: `val base_env : Eval_types.env` — the **only** export; the ~85 exclusive helpers are internal.
- **`Eval.base_env` has 28 external call sites** **[corrected 2026-08-25;** was 27 — re-count with `grep -rhoE '\bEval\.base_env\b' --include='*.ml' . | wc -l`**]** (distinct from `Typecheck.base_env`, which also exists and is unrelated). `eval.ml` MUST keep `let base_env = Eval_builtins.base_env`.

- [x] **Step 0: Classify the table's helper dependencies as shared or exclusive**

```bash
S=$(grep -n '^let base_env : env' lib/eval/eval.ml | cut -d: -f1)
E=$(grep -n '(\* Evaluation' lib/eval/eval.ml | cut -d: -f1)
awk -v s=$S -v e=$E 'NR>=s && NR<e' lib/eval/eval.ml | grep -oE '\b[a-z_][a-z0-9_]{3,}\b' | sort -u > /tmp/be-ids-$SLUG.txt
grep -oE '^let ([a-z_][a-z0-9_]*)' lib/eval/eval.ml | sed 's/^let //' | sort -u > /tmp/eval-defs-$SLUG.txt
awk -v s=$S -v e=$E 'NR<s || NR>=e' lib/eval/eval.ml > /tmp/eval-outside-$SLUG.txt
while read n; do echo "$(grep -cE "\b$n\b" /tmp/eval-outside-$SLUG.txt) $n"; done \
  < <(comm -12 /tmp/be-ids-$SLUG.txt /tmp/eval-defs-$SLUG.txt) | sort -rn
```

The number is how often the name appears in `eval.ml` *outside* the table. **≥ 3** (its definition plus real uses) → SHARED → `eval_runtime.ml`. **≤ 2** → table-EXCLUSIVE → moves *with* the table. Names already owned by `Eval_simd`/`Eval_net`/`Eval_session` (e.g. `f32_round`, `tcp_send_all`, `chan_*`, `csv_*`) are already siblings and need nothing.

The threshold is a starting classification, not an oracle. **The build is the arbiter:** an "exclusive" helper that `dune build` then reports missing from `eval.ml` was actually shared — move it to `eval_runtime.ml` and rebuild. Do not paper over it with a re-export from `eval_builtins`.

- [x] **Step 1: Extract `eval_runtime.ml` (the SHARED cluster), as its own commit**

Move every SHARED name from Step 0 — definitions plus the state cells they close over (the actor registry hashtable, the pid counters, the timer queue, the type tables). These are scattered across the `Actor runtime` (:144), `Dynamic Supervisor state` (:247), `Phase 1: Monitors, Links, and crash_actor` (:1796), and FFI-table sections **[all three [verified 2026-08-25]]**; move by name, not by range, and keep each moved definition's doc comment.

The cluster must itself satisfy the invariant: it may reference only `Eval_types`, `Eval_prim`, and the Phase-1 siblings. `spawn_child_actor` re-enters evaluation via `!eval_expr_hook` (:2249) **[verified 2026-08-25]** — that is already a hook call, so it moves cleanly. If any moved helper calls `eval_expr`/`apply` *directly*, route it through the `Eval_prim` hook first.

Then add re-exports in `eval.ml` for every moved name that is used **outside** `lib/eval`. Generate the list rather than guessing:

```bash
grep -rhoE '\bEval\.[a-z_][a-zA-Z0-9_]*' --include='*.ml' . | sort -u | sed 's/Eval\.//' > /tmp/eval-external-$SLUG.txt
comm -12 /tmp/eval-external-$SLUG.txt <(grep -oE '^let ([a-z_][a-z0-9_]*)' lib/eval/eval_runtime.ml | sed 's/^let //' | sort -u)
```

Each name printed gets `let <name> = Eval_runtime.<name>` in `eval.ml` (known at review: `actor_registry` 56 sites, `monitor_actor` 16, `ring_get` 12 — the exact set depends on what Step 0 classified).

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "ir_exit=$?"
scripts/run-tests.sh eval; echo "suite_exit=$?"
git add lib/eval/eval_runtime.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract shared runtime state to eval_runtime.ml"
```

- [x] **Step 2: Confirm the table's one-way dependency on the evaluator still holds**

```bash
S=$(grep -n '^let base_env : env' lib/eval/eval.ml | cut -d: -f1)
E=$(grep -n '(\* Evaluation' lib/eval/eval.ml | cut -d: -f1)
awk -v s=$S -v e=$E 'NR>=s && NR<e' lib/eval/eval.ml | grep -cE '\beval_(expr|decl|module)\b'
```

Expected: **0**. This is the load-bearing premise of the table move. If non-zero, the offending references must go through `!Eval_prim.eval_expr_hook` / `!Eval_prim.apply_hook` before proceeding.

- [x] **Step 3: Move the table AND its exclusive helpers into `eval_builtins.ml`**

```bash
{ echo '(** [base_env] — the delta-rule builtin table (core-march.md §4.4).'
  echo
  echo '    595 entries, plus the helpers only this table uses.  Extracted'
  echo '    verbatim from eval.ml — no behavior change.  This module is a LEAF'
  echo '    with respect to the evaluator: it calls no evaluator function'
  echo '    directly.  Where a builtin must re-enter evaluation it goes through'
  echo '    the [Eval_prim] hook refs ([eval_expr_hook], [apply_hook],'
  echo '    [run_scheduler_hook], [iface_dispatch_hook]) that eval.ml installs at'
  echo '    startup — the same indirection that existed before this extraction.'
  echo
  echo '    Shared runtime state (actor registry, scheduler, type tables) lives'
  echo '    in [Eval_runtime]; this module and [Eval] both depend on it. *)'
  echo
  echo 'open March_ast.Ast'
  echo 'open Eval_types'
  echo 'open Eval_prim'
  echo 'open Eval_runtime'
  echo
  awk -v s=$S -v e=$E 'NR>=s && NR<e' lib/eval/eval.ml
} > lib/eval/eval_builtins.ml
sed -i.bak "${S},$((E-1))d" lib/eval/eval.ml && rm lib/eval/eval.ml.bak
```

Then move each EXCLUSIVE helper from Step 0 into `eval_builtins.ml` **above** the table (by name, with its doc comment), deleting it from `eval.ml`. The build will name any you missed.

- [x] **Step 4: Write the interface file — export ONLY the table**

```ocaml
(** The delta-rule builtin environment.  See eval_builtins.ml.

    [base_env] is the sole export: the helpers behind it are implementation
    detail, and hiding them here is what keeps "is this helper already
    defined somewhere?" answerable. *)

val base_env : Eval_types.env
```

`Eval_types.env` is `(string * value) list`, created in Task 1.0. This signature is exact.

- [x] **Step 5: Add the re-export to `eval.ml`**

At the position the table used to occupy:

```ocaml
(* [base_env] moved to eval_builtins.ml (5,274 lines, 595 entries).  Re-exported
   here because [Eval.base_env] has 28 external call sites across the compiler
   and test suite. *)
let base_env = Eval_builtins.base_env
```

- [x] **Step 6: Build, verify IR, run the FULL suite**

This is the largest single move in the plan; the eval suite alone is not enough.

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "ir_exit=$?"
scripts/run-tests.sh > /tmp/suite-t13-$SLUG.log 2>&1; echo "suite_exit=$?"; diff <(grep -oE '[0-9]+ (passed|failed)' /tmp/suite-base-$SLUG.log) <(grep -oE '[0-9]+ (passed|failed)' /tmp/suite-t13-$SLUG.log)
```

Expected: `ir_exit=0`, `suite_exit=0`, and an empty diff of the pass/fail counts.

- [x] **Step 7: Commit**

```bash
git add lib/eval/eval_builtins.ml lib/eval/eval_builtins.mli lib/eval/eval.ml && git commit -m "refactor(eval): extract 590-entry base_env builtin table to eval_builtins.ml"
```

### Task 1.4: Add § navigation headers to what remains

**Files:** Modify `lib/eval/eval.ml`

- [x] **Step 1: Number the existing section headers**

`eval.ml` already has 70 header comments but they are unnumbered rules (`(* ---- *)`), so they cannot be jumped to by name. Convert the ~34 titled ones to the numbered form `typecheck.ml` uses:

```ocaml
(* =================================================================
   §7  Pattern matching
   ================================================================= *)
```

Keep the existing titles verbatim (`Value type`, `Actor runtime`, `Dynamic Supervisor state`, `Tap bus`, `Ring buffer helpers`, `Debug trace types`, `Exceptions`, `March call stack for backtraces`, `Pattern matching`, `Built-in environment`, `FFI extern stub table`, `Dynamic FFI`, `FFI Marshal Layer`, `Show dispatch helper`, `Evaluation`, `Task builtins`, `App / Supervisor machinery`, `Module evaluation`, `Test runner`, `Doctest runner`). Number them in file order.

- [x] **Step 2: Add a table of contents at the top of the file**

Immediately below the module docstring, list every § with its title. This is what makes the file greppable by concept rather than by symbol.

- [x] **Step 3: Verify comments-only, then commit**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "exit=$?"
git add lib/eval/eval.ml && git commit -m "docs(eval): number section headers and add a table of contents"
```

### Task 1.5: Phase 1 exit gate — the interpreter-performance control (ADDED 2026-08-25)

**Files:** none modified except the appended benchmark record.

Phase 1 is the one phase the IR oracle cannot police (Task 0.3). Do not declare Phase 1 done on a green suite alone.

- [x] **Step 1: Re-run the interpreted benchmarks and compare against the Task 0.3 baseline**

```bash
bash bench/run_interp_bench.sh --modes interp --runs 3 --tag decomp-phase1-$(git rev-parse --short HEAD)
```

Compare median-ms per benchmark against the `decomp-baseline-8d2b22fb` rows in
`bench/results/2026-08-25-interp-arm64.jsonl`.

**Pass condition:** no benchmark's median is more than **5%** slower than the baseline.
A pure code move must cost nothing; 5% is headroom for this box's noise, not a budget to spend.

- [x] **Step 2: If a benchmark regressed, look for a hook that used to be a direct call**

The specific mechanism to suspect — the one Phase 1's own design introduces — is an extracted
function reaching the evaluator through `!Eval_prim.eval_expr_hook` / `!apply_hook` where the
pre-extraction code called `eval_expr` / `apply` directly. That converts a static call into a
`ref` load plus an indirect call in the interpreter's hot path. It is invisible to the type
checker, invisible to the suites, invisible to the IR oracle, and reads in the diff as an
innocuous "route through the existing hook".

```bash
git diff <phase1-base>..HEAD -- lib/eval/ | grep -nE '^\+.*!(eval_expr_hook|apply_hook|run_scheduler_hook|iface_dispatch_hook)'
```

Every hit must correspond to a `-` line that *already* dereferenced that hook. A `+` hook
deref with no matching `-` is a new indirection: it is a semantic change wearing a code-move
costume, and it does not belong in a Phase-1 commit.

**Interpretation caveats before believing a regression:** this box is shared and heavily
loaded. Slow-but-flat RSS means load, not regression; check `uptime` before and after. And the
first timed variant in a run pays ~25% warmup — compare like position to like position, or
re-run with the order reversed.

- [x] **Step 3: Commit the record**

```bash
git add bench/results/2026-08-25-interp-arm64.jsonl && git commit -m "bench: record interpreter timings after eval.ml decomposition"
```

---

## Phase 2 — `llvm_emit.ml`: the 3,985-line function — **LANDED 2026-08-26**

> **Outcome:** `llvm_emit.ml` 5,719 → 4,798 lines; `emit_expr` 4,319 → 3,878;
> `llvm_emit.mli` 44 → 12 `val`s. IR oracle IDENTICAL across 240 programs at
> every one of five checkpoints — including after Tasks 2.1/2.2, which this
> plan predicted would "legitimately change" the IR. They do not: converting
> string-guard dispatch to a variant changes how the compiler decides, not
> what it writes. Full record, including four factual corrections to this
> phase and the one deviation, in
> `specs/progress/2026-08-26-llvm-emit-decomposition-phase2.md`.
>
> **Corrections:** the builtin count is **57** (this phase says 50 in one place
> and 58 in another); `root_cap` gets no constructor (it is dispatched in
> `emit_atom`); `task_await` has **one** arm, not two; `emit_expr` has **no
> external caller**.
>
> **Deviation — Task 2.2 Step 2's consolidation was rejected as unsound.**
> Six non-builtin arms (`is_int_bitwise`, `record_keys/values/entries`, the
> mutual- and self-TCO arms, the sentinel arm, the four SIMD arms) sit between
> the first and last builtin arm. Hoisting all 57 names' every arity above them
> changes fall-through for unhandled arities and flips TCO precedence for every
> builtin currently dispatched below the TCO arms — a change no corpus program
> exercises, so the oracle cannot see it. Guards were converted **in place**
> instead, and the exhaustiveness surface is `Llvm_emit.builtin_group`, a
> wildcard-free match over `Builtin_name.t` (proven to fire with a `Probe_unused`
> constructor). Task 2.3 followed: with no `emit_builtin` to carve, the split
> took the order-preserving seam — `llvm_emit_simd.ml` (585) and
> `llvm_emit_nmap.ml` (433). The arith/task/record arm **bodies** remain inline;
> extracting them is per-arm delegation and is left open. The accidental
> builtin-vs-TCO arm ordering is filed as
> `specs/todos/2026-08-26-builtin-arm-order-vs-tco-arms-is-accidental.md`.

**[corrected 2026-08-25] — every `llvm_emit.ml` line number in this phase moved.** `emit_expr` now starts at **:1348** (was ~:1222) and ends at **:5666**; everything the 2026-08-23 review recorded is stale by roughly +126. The table at the end of this section maps old → new. **Do not paste a literal from this phase without re-deriving it.**

`emit_expr` is 76% of its file (**4,319 of 5,719** lines at `8d2b22fb`; 4,298 of 5,659 at `e9adc190`; 3,985 of 5,255 at `1f5a0111` — it keeps growing, which is the argument for the phase): a flat **100+-arm match** in which **57** arms dispatch on a raw string (`when f.Tir.v_name = "task_await"`) and 7 more on `is_*` predicates. Two properties make it the highest-risk file in the compiler:

1. **Arm order is semantically load-bearing.** The specialized `ELet (tmp_v, EApp …)` arms at **:1408** and **:1566** (self-TCO and mutual-TCO respectively) shadow the generic `ELet` at **:1667**. An arm inserted in the wrong place silently never fires — no type error, no test failure unless a test covers that exact builtin.
2. **String-keyed dispatch is invisible to the compiler.** Nothing checks the 50-name set for exhaustiveness, overlap, or typos. This is the mechanism behind this repo's recurring builtin-multi-site bug class.

**Important:** this conversion is behavior-preserving, so **the IR oracle applies to Phase 2 exactly as it does to Phase 1**. A correct variant conversion emits byte-identical IR. Do not accept "the IR changed but I think it's fine" — if IR changes, the conversion is wrong.

### Task 2.1: Introduce `Builtin_name.t`

**Files:**
- Create: `lib/tir/builtin_name.ml`, `lib/tir/builtin_name.mli`
- Modify: `lib/tir/dune` — **explicit `(modules …)` list; the new module is silently not compiled until added**

**Interfaces:**
- Produces: `type t` with one constructor per emitted builtin (**57** at `8d2b22fb`); `val of_string : string -> t option`; `val to_string : t -> string`; `val all : t list`.

- [x] **Step 1: Regenerate the authoritative name list from the source**

Do not copy the list from this plan — derive it, so the task cannot drift from the code. **[corrected 2026-08-25]** — the draft hard-coded the window as `NR>1222 && NR<5210`; those numbers now cut into the middle of `emit_expr`. Derive the window from `emit_expr`'s own boundaries:

```bash
S=$(grep -n '^let rec emit_expr ctx' lib/tir/llvm_emit.ml | cut -d: -f1)
E=$(awk -v s=$S 'NR>s && /^let |^and /{print NR; exit}' lib/tir/llvm_emit.ml)
echo "emit_expr = $S..$((E-1))"     # 1348..5666 at 8d2b22fb
awk -v s=$S -v e=$E 'NR>s && NR<e' lib/tir/llvm_emit.ml \
  | grep -oE 'v_name = "[a-z0-9_.]+"' | sed 's/v_name = //' | tr -d '"' | sort -u
```

Expected at `8d2b22fb`: **57** names —
`actor_register actor_reply bool_to_string chan_choose chan_send float_to_string get_work_pool html_auto_escape html_escape_ctx int_abs int_div int_div_euclid int_max_value int_min_value int_mod int_mod_euclid int_not int_popcount int_pow int_to_string mpst_send negate not pmap_threshold receive record_from_list record_get record_has_key record_put remote_ref_hashes send signal_raise_self signal_unwatch signal_watch task_await task_await_unwrap task_cancel task_cancel_by_id task_cancel_token_new task_is_cancelled task_reductions task_spawn task_spawn_steal task_spawn_with_cancel task_yield to_string vault_drop vault_get vault_incr vault_ns_drop vault_ns_get vault_ns_set vault_push_capped vault_put_new vault_set vault_set_ttl vault_update`.

The trajectory: **50** at `1f5a0111` → **58** claimed at `e9adc190` → **57** now. Two corrections to the review's list **[corrected 2026-08-25]**:

- **`root_cap` is not one of them.** It is dispatched in `emit_atom` (`llvm_emit.ml:389`, `Tir.AVar v when v.Tir.v_name = "root_cap"`), not in `emit_expr`. The review's 58 came from a window whose numbers no longer mean what they meant; `root_cap` must **not** get a `Builtin_name` constructor, because `Builtin_name.t` is defined as the set `emit_expr` dispatches and adding an atom-level name to it would make the exhaustiveness surface lie.
- The nine genuinely added since `1f5a0111` are `vault_drop vault_get vault_incr vault_ns_drop vault_ns_get vault_ns_set vault_update` plus the two that were already listed — i.e. all `vault_*`. That a `vault_*` family kept growing arm-by-arm across three measurements is precisely the drift this variant exists to catch.

If the count differs from what this plan says, **the command wins** — use what it prints, add the constructors, and note the drift in the commit message. The constructor list printed in Step 2 below is from `1f5a0111` and is **incomplete on purpose**; treat it as a formatting example, not as data.

- [x] **Step 2: Write `builtin_name.ml`**

```ocaml
(** Codegen-dispatched builtin names, as a variant rather than raw strings.

    [emit_expr] previously dispatched 57 builtins with
    [when f.Tir.v_name = "task_await"] guards.  Nothing checked that set for
    exhaustiveness, overlap, or typos, so a builtin added to one emitter site
    and forgotten at another failed SILENTLY — the arm simply never fired and
    the generic fallback emitted plausible-but-wrong code.

    Making the set a closed variant moves that failure to compile time: adding
    a constructor here without handling it in [Llvm_emit] is a non-exhaustive
    match warning, which this project builds as an error.

    ONLY names dispatched by the LLVM emitter belong here.  Interpreter-only
    builtins live in [Eval_builtins.base_env]; the two sets deliberately
    differ. *)

type t =
  | Actor_register
  | Actor_reply
  | Bool_to_string
  | Chan_choose
  | Chan_send
  | Float_to_string
  | Get_work_pool
  | Html_auto_escape
  | Html_escape_ctx
  | Int_abs
  | Int_div
  | Int_div_euclid
  | Int_max_value
  | Int_min_value
  | Int_mod
  | Int_mod_euclid
  | Int_not
  | Int_popcount
  | Int_pow
  | Int_to_string
  | Mpst_send
  | Negate
  | Not
  | Pmap_threshold
  | Receive
  | Record_from_list
  | Record_get
  | Record_has_key
  | Record_put
  | Remote_ref_hashes
  | Send
  | Signal_raise_self
  | Signal_unwatch
  | Signal_watch
  | Task_await
  | Task_await_unwrap
  | Task_cancel
  | Task_cancel_by_id
  | Task_cancel_token_new
  | Task_is_cancelled
  | Task_reductions
  | Task_spawn
  | Task_spawn_steal
  | Task_spawn_with_cancel
  | Task_yield
  | To_string
  | Vault_push_capped
  | Vault_put_new
  | Vault_set
  | Vault_set_ttl

(* [all] and [to_string] are the single source of truth.  [of_string] is
   derived from them, so a new constructor cannot be added to one direction
   and forgotten in the other. *)
let to_string = function
  | Actor_register -> "actor_register"
  | Actor_reply -> "actor_reply"
  | Bool_to_string -> "bool_to_string"
  | Chan_choose -> "chan_choose"
  | Chan_send -> "chan_send"
  | Float_to_string -> "float_to_string"
  | Get_work_pool -> "get_work_pool"
  | Html_auto_escape -> "html_auto_escape"
  | Html_escape_ctx -> "html_escape_ctx"
  | Int_abs -> "int_abs"
  | Int_div -> "int_div"
  | Int_div_euclid -> "int_div_euclid"
  | Int_max_value -> "int_max_value"
  | Int_min_value -> "int_min_value"
  | Int_mod -> "int_mod"
  | Int_mod_euclid -> "int_mod_euclid"
  | Int_not -> "int_not"
  | Int_popcount -> "int_popcount"
  | Int_pow -> "int_pow"
  | Int_to_string -> "int_to_string"
  | Mpst_send -> "mpst_send"
  | Negate -> "negate"
  | Not -> "not"
  | Pmap_threshold -> "pmap_threshold"
  | Receive -> "receive"
  | Record_from_list -> "record_from_list"
  | Record_get -> "record_get"
  | Record_has_key -> "record_has_key"
  | Record_put -> "record_put"
  | Remote_ref_hashes -> "remote_ref_hashes"
  | Send -> "send"
  | Signal_raise_self -> "signal_raise_self"
  | Signal_unwatch -> "signal_unwatch"
  | Signal_watch -> "signal_watch"
  | Task_await -> "task_await"
  | Task_await_unwrap -> "task_await_unwrap"
  | Task_cancel -> "task_cancel"
  | Task_cancel_by_id -> "task_cancel_by_id"
  | Task_cancel_token_new -> "task_cancel_token_new"
  | Task_is_cancelled -> "task_is_cancelled"
  | Task_reductions -> "task_reductions"
  | Task_spawn -> "task_spawn"
  | Task_spawn_steal -> "task_spawn_steal"
  | Task_spawn_with_cancel -> "task_spawn_with_cancel"
  | Task_yield -> "task_yield"
  | To_string -> "to_string"
  | Vault_push_capped -> "vault_push_capped"
  | Vault_put_new -> "vault_put_new"
  | Vault_set -> "vault_set"
  | Vault_set_ttl -> "vault_set_ttl"

let all =
  [ Actor_register; Actor_reply; Bool_to_string; Chan_choose; Chan_send;
    Float_to_string; Get_work_pool; Html_auto_escape; Html_escape_ctx;
    Int_abs; Int_div; Int_div_euclid; Int_max_value; Int_min_value; Int_mod;
    Int_mod_euclid; Int_not; Int_popcount; Int_pow; Int_to_string; Mpst_send;
    Negate; Not; Pmap_threshold; Receive; Record_from_list; Record_get;
    Record_has_key; Record_put; Remote_ref_hashes; Send; Signal_raise_self;
    Signal_unwatch; Signal_watch; Task_await; Task_await_unwrap; Task_cancel;
    Task_cancel_by_id; Task_cancel_token_new; Task_is_cancelled;
    Task_reductions; Task_spawn; Task_spawn_steal; Task_spawn_with_cancel;
    Task_yield; To_string; Vault_push_capped; Vault_put_new; Vault_set;
    Vault_set_ttl ]

let table : (string, t) Hashtbl.t =
  let h = Hashtbl.create 64 in
  List.iter (fun c -> Hashtbl.replace h (to_string c) c) all;
  h

let of_string s = Hashtbl.find_opt table s
```

- [x] **Step 3: Write `builtin_name.mli`**

```ocaml
(** Codegen-dispatched builtin names.  See builtin_name.ml. *)

type t =
  | Actor_register | Actor_reply | Bool_to_string | Chan_choose | Chan_send
  | Float_to_string | Get_work_pool | Html_auto_escape | Html_escape_ctx
  | Int_abs | Int_div | Int_div_euclid | Int_max_value | Int_min_value
  | Int_mod | Int_mod_euclid | Int_not | Int_popcount | Int_pow | Int_to_string
  | Mpst_send | Negate | Not | Pmap_threshold | Receive | Record_from_list
  | Record_get | Record_has_key | Record_put | Remote_ref_hashes | Send
  | Signal_raise_self | Signal_unwatch | Signal_watch | Task_await
  | Task_await_unwrap | Task_cancel | Task_cancel_by_id | Task_cancel_token_new
  | Task_is_cancelled | Task_reductions | Task_spawn | Task_spawn_steal
  | Task_spawn_with_cancel | Task_yield | To_string | Vault_push_capped
  | Vault_put_new | Vault_set | Vault_set_ttl

val to_string : t -> string
val of_string : string -> t option

(** Every constructor, used by the round-trip test. *)
val all : t list
```

- [x] **Step 4: Add the module to `lib/tir/dune` — REQUIRED**

The `(modules …)` list is explicit. Insert `builtin_name` at the front, next to `tir_names`:

```
 (modules builtin_name tir_names rc_types tir pp trmc lower_types lower_state ...)
```

Keep `to_string`/`all` in sync with what Step 1 printed — 57 constructors at `8d2b22fb`, including the seven `vault_*` names the draft's list omits, and **excluding** `root_cap`.

- [x] **Step 5: Write the round-trip test**

Add to `test/test_codegen.ml`:

```ocaml
let test_builtin_name_roundtrip () =
  List.iter
    (fun c ->
      let s = March_tir.Builtin_name.to_string c in
      match March_tir.Builtin_name.of_string s with
      | Some c' when c' = c -> ()
      | Some _ -> Alcotest.failf "builtin %S round-tripped to a different constructor" s
      | None -> Alcotest.failf "builtin %S has no of_string entry" s)
    March_tir.Builtin_name.all;
  (* Every name the emitter dispatches must be known to the variant. *)
  (* Keep this literal equal to the regenerated list's length (Step 1);
     it is the tripwire that a new emit arm was added without a constructor. *)
  Alcotest.(check int) "constructor count" 57
    (List.length March_tir.Builtin_name.all)
```

Register it in the same list the other `test_codegen` cases use.

- [x] **Step 6: Build and run**

```bash
dune build --root . test/run_codegen.exe 2>&1 | tail -5 && ./_build/default/test/run_codegen.exe -e 2>&1 | tail -5; echo "exit=$?"
```

Expected: exit 0, the new test passing. `builtin_name.ml` is not yet referenced by the emitter, so IR must still be identical:

```bash
dune build --root . bin/main.exe && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "exit=$?"
```

- [x] **Step 7: Commit**

```bash
git add lib/tir/builtin_name.ml lib/tir/builtin_name.mli lib/tir/dune test/test_codegen.ml && git commit -m "feat(tir): add Builtin_name variant for codegen-dispatched builtins"
```

### Task 2.2: Convert `emit_expr`'s string guards to the variant

**Files:** Modify `lib/tir/llvm_emit.ml`

**Interfaces:**
- Consumes: `March_tir.Builtin_name.of_string` from Task 2.1.

- [x] **Step 1: Understand what must NOT move**

```bash
S=$(grep -n '^let rec emit_expr ctx' lib/tir/llvm_emit.ml | cut -d: -f1)
awk -v s=$S 'NR>=s && NR<s+460 && /^  \| /{print NR": "substr($0,1,72)}' lib/tir/llvm_emit.ml
```

**[corrected 2026-08-25]** — the draft's window `NR>1222 && NR<1610` predates `emit_expr` moving to `:1348`; it now starts *above* the function and stops mid-way through the structural arms.

The structural arms — `EAtom` (**:1352**), the `ELet` fv-field arm (**:1359**), the four specialized `ELet (tmp_v, EApp …)` / `ESeq (EApp …, dec_chain)` TCO arms (**:1408**, **:1485** self-TCO; **:1566**, **:1619** mutual-TCO), the generic `ELet` (**:1667**) and `ESeq` (**:1705**) — **must keep their exact current relative order**.

Old → new, so a stale reference elsewhere can be recognised rather than silently mis-applied. **Note the trap:** `:1359` was a *specialized* arm in the draft and is a *different* arm at that same number today, so a stale pointer here does not fail loudly.

| draft (`1f5a0111`/`e9adc190`) | `8d2b22fb` | arm |
|---|---|---|
| :1233 | **:1352** | `EAtom` |
| :1282 | **:1408** | specialized `ELet`, self-TCO |
| :1359 | **:1485** | specialized `ESeq`, self-TCO |
| :1440 | **:1566** | specialized `ELet`, mutual-TCO |
| :1493 | **:1619** | specialized `ESeq`, mutual-TCO |
| :1541 | **:1667** | generic `ELet` |
| :1579 | **:1705** | `ESeq` |
| :1607 | **:1733** | `is_int_arith` predicate arm |
| :1644 | **:1770** | `is_int_cmp` predicate arm |
| :1824 | **:1950** | `is_float_arith` predicate arm |
| :1839 | **:1965** | `"&&"` string guard (NOT in the variant) |
| :1846 | **:1972** | `"||"` string guard (NOT in the variant) |
| :1853 | **:1979** | `not` — the first **in-variant** arm; this is where the consolidated dispatch arm goes |
| :1896 / :1921 | **:2022 / :2047** | `html_auto_escape`, still two arms |
| :2121 | **:2255** | `int_popcount` |
| :2201 (+ :2269) | **:2436** *(single arm)* | `task_await` — see below |
| — | **:2849** | `int_max_value` | They pattern-match on TIR *shape*, not on builtin name, and the specialized ones deliberately shadow the generic ones. Only the `EApp (f, args) when f.Tir.v_name = "…"` arms are in scope for this task.

- [x] **Step 2: Convert one arm first and prove the technique**

Start with `int_popcount` (**:2255**, was :2121) — single argument, no control flow, easy to eyeball. Change:

```ocaml
  | Tir.EApp (f, [a]) when f.Tir.v_name = "int_popcount" ->
```

to a match on the decoded variant. Introduce a single guarded dispatch arm placed **where the first in-variant name arm currently sits** — that is `not` at **:1979**. The symbolic-operator string guards above it (`"&&"` **:1965**, `"||"` **:1972**) are NOT in the variant and keep their own arms, and the predicate arms (`is_int_arith` **:1733**, `is_int_cmp` **:1770**, `is_float_arith` **:1950**) stay exactly where they are. **[all corrected 2026-08-25]** That placement keeps ordering relative to the structural and predicate arms unchanged:

```ocaml
  | Tir.EApp (f, args) when Builtin_name.of_string f.Tir.v_name <> None ->
      emit_builtin ctx (Option.get (Builtin_name.of_string f.Tir.v_name)) f args
```

and define `emit_builtin` as a new mutually-recursive function (`and emit_builtin ctx b f args = match b with …`) carrying the converted arms.

**Fall-through semantics change here — handle it explicitly.** Today `| Tir.EApp (f, [a]) when f.Tir.v_name = "task_await"` matches only the 1-arg shape; any other shape falls through to the later generic-application arms. The consolidated arm captures *every* arity for all 57 names, so `emit_builtin` must provide that escape itself. Factor the body of the current generic `EApp` arm into a callable `and emit_generic_app ctx f args = …`, and inside `emit_builtin` give every constructor's shape-match a final `| _ -> emit_generic_app ctx f args` arm:

```ocaml
and emit_builtin ctx (b : Builtin_name.t) f args =
  match b with
  | Builtin_name.Task_await ->
      (match args with
       | [a] -> (* body of the :2436 arm, verbatim — ONE arity, see Step 4 *)
       | _ -> emit_generic_app ctx f args)
  | Builtin_name.Int_popcount ->
      (match args with
       | [a] -> (* body of the :2255 arm, verbatim *)
       | _ -> emit_generic_app ctx f args)
  (* … one outer arm per constructor, no outer wildcard … *)
```

The outer match on `b` is the exhaustiveness surface (Step 5); the inner matches on `args` keep the generic escape. That is fall-through preservation, not a hole.

- [x] **Step 3: Verify after the FIRST arm, before converting the other 56**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "exit=$?"
```

Expected: `IR IDENTICAL`, `exit=0`. **If IR changed here, stop and diagnose** — the technique is wrong and converting 56 more arms will bury the cause.

- [x] **Step 4: Convert the remaining 56 arms in batches of ~10**

After each batch: rebuild, run the oracle, and only then continue. A batch that changes IR is reverted and redone one arm at a time.

One arm needs care because its guard is not simple equality:
- `html_auto_escape` appears **twice** (**:2022**, **:2047**) with different shapes. Preserve both, distinguished inside `emit_builtin` by matching on `args`, in the same order.

**[corrected 2026-08-25] `task_await` no longer appears twice.** The draft named two arms (:2201, :2269); today there is exactly **one**, at **:2436**, and the separate consuming variant is `task_await_unwrap` at **:2342** — a distinct builtin with its own constructor, not a second arity of `task_await`. Re-derive before writing the arm:

```bash
grep -n 'f.Tir.v_name = "task_await"' lib/tir/llvm_emit.ml   # expect exactly 1 hit
```

If you build `emit_builtin`'s `Task_await` case around an imagined two-arity split, the second branch is dead code that no test can reach — and dead codegen branches are exactly how this repo's compiled-only bugs get planted.

- [x] **Step 5: Make the match exhaustive**

Once all 57 are converted, `emit_builtin`'s **outer match on the constructor** must have no `| _ ->` arm, so that adding a constructor to `Builtin_name.t` becomes a compile error (warning 8 is an error under the dev profile — verified). The inner per-constructor matches on `args` DO keep their `emit_generic_app` escape — that is the fall-through preservation from Step 2, not a catch-all over constructors. Confirm:

```bash
grep -n 'and emit_builtin' lib/tir/llvm_emit.ml
```

Then read the function's final arm and verify it is a named constructor, not a wildcard.

- [x] **Step 6: Prove the exhaustiveness check actually fires**

```bash
sed -i.bak 's/^  | Vault_set_ttl$/  | Vault_set_ttl\n  | Probe_unused/' lib/tir/builtin_name.ml && dune build --root . bin/main.exe 2>&1 | grep -c 'not exhaustive\|Error'
```

Expected: a non-zero count — the build **fails**. That is the whole point of the task. Revert:

```bash
git checkout lib/tir/builtin_name.ml && rm -f lib/tir/builtin_name.ml.bak && dune build --root . bin/main.exe 2>&1 | tail -3
```

- [x] **Step 7: Full verification**

```bash
scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "ir_exit=$?"
scripts/run-tests.sh > /tmp/suite-t22-$SLUG.log 2>&1; echo "suite_exit=$?"
./_build/default/test/run_snapshots.exe -e > /tmp/snap-t22-$SLUG.log 2>&1; echo "snap_exit=$?"
```

Expected: all three exit 0. IR identical is the strong claim here — the refactor changed dispatch mechanism, not emitted code.

- [x] **Step 8: Commit and record the user-visible change**

Add to `CHANGELOG.md` under `## [Unreleased]` → `### Changed`:

```markdown
- Codegen builtin dispatch is now a closed variant (`Builtin_name.t`) rather than
  string comparison, so a builtin added to the IR emitter without an emission arm
  is a compile error instead of a silently-wrong fallback.
```

```bash
git add lib/tir/llvm_emit.ml CHANGELOG.md && git commit -m "refactor(tir): dispatch emit_expr builtins through Builtin_name variant"
```

### Task 2.3: Split the converted arms into topic modules

**Files:**
- Create: `lib/tir/llvm_emit_arith.ml`, `lib/tir/llvm_emit_task.ml`, `lib/tir/llvm_emit_record.ml`
- Modify: `lib/tir/llvm_emit.ml`, `lib/tir/dune`

- [x] **Step 1: Add all three modules to `lib/tir/dune`'s `(modules …)` list**

Do this **first**, in the same commit — a module missing from the list is silently not compiled, and the resulting error is confusing.

- [x] **Step 2: Move `emit_builtin`'s arms by topic**

- `llvm_emit_arith.ml`: `Int_abs`, `Int_div`, `Int_div_euclid`, `Int_max_value`, `Int_min_value`, `Int_mod`, `Int_mod_euclid`, `Int_not`, `Int_popcount`, `Int_pow`, `Int_to_string`, `Bool_to_string`, `Float_to_string`, `Negate`, `Not`, `To_string`
- `llvm_emit_task.ml`: all `Task_*`, `Actor_*`, `Signal_*`, `Send`, `Receive`, `Chan_*`, `Mpst_send`, `Get_work_pool`, `Pmap_threshold`, `Remote_ref_hashes`
- `llvm_emit_record.ml`: all `Record_*`, all `Vault_*`, both `Html_*`

Each module exports one function taking the emitter context, e.g. `val emit : Llvm_ctx.t -> Builtin_name.t -> Tir.value -> Tir.atom list -> (string * string) option`, returning `None` for a constructor it does not own. `emit_builtin` in `llvm_emit.ml` becomes a three-way chain that **must still end in an exhaustive match** — keep a final `match b with` listing every constructor and routing it, so exhaustiveness is preserved across the split.

- [x] **Step 3: Verify and commit**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "ir_exit=$?"
scripts/run-tests.sh codegen; echo "suite_exit=$?"
git add lib/tir/llvm_emit_arith.ml lib/tir/llvm_emit_task.ml lib/tir/llvm_emit_record.ml lib/tir/llvm_emit.ml lib/tir/dune && git commit -m "refactor(tir): split emit_builtin arms into arith/task/record modules"
```

---

## Phase 3 — `refine_check.ml`: navigation and the 12-parameter flood

**[verified 2026-08-25]** — `refine_check.ml` is untouched by the perf project: still 7,416 lines, `check_call` still at `:3371–4731` (1,361 lines), still three call sites at `:5695` / `:5719` / `:5731`. Every number in this phase re-measured correct.

7,416 lines with **zero section headers** — the only file in this set with no navigational structure at all. `check_call` is 1,361 lines behind a twelve-parameter signature. It has **three** call sites, all inside the `visit` traversal (`refine_check.ml:5695`, `:5719`, `:5731`), so the parameter bundle can be changed with a bounded blast radius — but all three must be read, not one.

**The IR oracle does not apply here** — refinement checking affects diagnostics, not emitted code. Phase 3 needs its own oracle, and building it requires clearing two caches that otherwise produce vacuous green:

- `--refine-report` prints nothing on a warm CAS. Clear `.march/cas/artifacts-v2/` (**not** `artifacts/`, which is an inert v1 pointer store).
- The refinement VC cache masks regression tests. Clear `.march/cas/vc` **once before** a verdict run, never during one.

### Task 3.1: Build the refinement diagnostic oracle

**Files:** Create `scripts/refine-oracle.sh`

- [x] **Step 1: Write the script**

The script now lives in the repo — **read `scripts/refine-oracle.sh`, do not re-type
the draft that used to sit inline here.** That draft **could never run**: it repeated,
verbatim, the `${x:?…}` bug already documented one phase up in Task 0.1 —

```bash
MODE="${1:?usage: refine-oracle.sh {baseline|check} <dir>}"   # BROKEN
```

Bash ends a `${x:?word}` expansion at the **first** `}`, which here is the one inside
`{baseline|check}`, so `MODE` came out as `baseline <dir>}` and every invocation died
with `unknown mode` before touching a fixture. Task 0.1's copy was annotated `# BROKEN`
on 2026-08-25; **this copy was missed and stayed live until 2026-08-26**. The committed
script keeps the usage text in a `}`-free `USAGE` variable. **[corrected 2026-08-26]**

The committed version differs from the draft in two further ways, both found by running it:

- **It runs under a private `HOME`.** `~/.cache/march` holds the Marshal'd stdlib AST and
  typecheck env (`bin/main.ml`'s `stdlib_decls` / `get_stdlib_tc_env`), keyed by stdlib
  content plus compiler build id and **shared by every worktree on the box**. The
  marshalled spans carry the absolute paths of whichever worktree populated the blob, so
  stdlib diagnostics print *another agent's directory* and the manifest moves with nobody
  touching the checker — measured as 14 phantom `stdlib_prelude` lines on the first
  green control run. This is a third shared cache beyond the two the draft names, and it
  does not live under `.march/`.
- **It normalises stdlib path prefixes**, because the compiler reaches `prelude.march`
  as either the staged `_build/default/bin/../stdlib/…` copy or the source tree and the
  spelling is not a property of the checker.

It also guards on fixture count as well as line count: a sweep that visits fewer than
100 fixtures is refused, not just one that prints fewer than 50 lines.

- [x] **Step 2: Record the baseline and prove it is non-vacuous**

```bash
chmod +x scripts/refine-oracle.sh && scripts/refine-oracle.sh baseline /tmp/refine-base-$SLUG; echo "exit=$?"
```

Measured 2026-08-26: `fixtures=297 report_lines=5638`, exit 0, **6m12s**. A
`FATAL:` line means the cache clear did not take — investigate before proceeding.
Let it finish; a half-run baseline is worse than none.

**Non-vacuity, executed 2026-08-26** (an oracle nobody has seen fail is not evidence):

*RED probe* — two perturbations inside `refine_check.ml`, one message and one verdict:
`"was NOT verified here"` → `"was NOT PROBEVERIFIED here"`, and in `check_call`'s
discharge, `| Refine.Verified -> note Obligation.Proved` →
`note (Obligation.Skipped Obligation.Solver_undecided)`. Result:
`DIAGNOSTICS CHANGED — 1528 differing lines`, exit 1 (33 of them the reworded message,
the rest proved/skipped counts across the corpus).

*GREEN control* — probe reverted, a comment-only line appended to the same file, rebuilt:
`REFINEMENT DIAGNOSTICS IDENTICAL (5638 lines over 297 fixtures)`, exit 0.

- [x] **Step 3: Commit**

```bash
git add scripts/refine-oracle.sh && git commit -m "test: add refinement-diagnostic oracle for refine_check refactors"
```

### Task 3.2: Add § section headers

**Files:** Modify `lib/refinecheck/refine_check.ml`

- [ ] **Step 1: Identify natural boundaries**

```bash
grep -n '^let [a-z_]*' lib/refinecheck/refine_check.ml | head -60
```

Group the 197 top-level definitions into ~12 sections by concern (SMT sort management, path/scope fact channels, record sorts, precondition checking, postcondition checking, induction, capability walks, the `visit` traversal, entry points).

- [ ] **Step 2: Insert numbered headers in the same style as `typecheck.ml`**

```ocaml
(* =================================================================
   §5  Precondition checking
   ================================================================= *)
```

- [ ] **Step 3: Add a table of contents below the module docstring**

- [ ] **Step 4: Verify comments-only and commit**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3 && scripts/refine-oracle.sh check /tmp/refine-base-$SLUG; echo "exit=$?"
git add lib/refinecheck/refine_check.ml && git commit -m "docs(refinecheck): add numbered section headers and a table of contents"
```

### Task 3.3: Bundle `check_call`'s parameters into a record

**Files:** Modify `lib/refinecheck/refine_check.ml`

**Interfaces:**
- Produces: `type call_ctx = { root : …; errctx : …; lets : launder; postcond : string -> A.expr list -> (string * A.expr * string option) option; rp : rparam; sc : scope; re : recenv }` — the seven parameters that are *constant across the whole traversal*. The four that vary per call (`~span`, `~callee`, `sg`, `args`, `path`) stay as explicit parameters.

- [ ] **Step 1: Read the current signature and classify each parameter**

```bash
S=$(grep -n '^let check_call ' lib/refinecheck/refine_check.ml | cut -d: -f1)
sed -n "${S},$((S+5))p" lib/refinecheck/refine_check.ml    # 3371..3376 at 8d2b22fb
```

Current: `~root errctx ~span ~(callee : string) ?(subject = Argument) ?(verdict_out) ~(lets : launder) ~(postcond) (sg : fn_sig) (args) (path) (rp : rparam) (sc : scope) (re : recenv)`.

Classify by tracing **all three call sites** — `refine_check.ml:5695`, `:5719`, `:5731`, all inside the `visit` traversal: a parameter passed unchanged at every site on every iteration is *context*; one that varies at **any** site is a *parameter*. Do not guess, and do not stop after the first site — an argument constant at one can vary at another.

- [ ] **Step 2: Define the record next to `check_call`, with a docstring per field**

Each field's comment says what it is and why it is threaded — this is the documentation that does not exist today and is the main reason the function is hard to edit.

- [ ] **Step 3: Change the signature and all three call sites**

Build the record once, where `visit` binds the traversal-constant values, and pass it at `:5695`, `:5719`, and `:5731`.

- [ ] **Step 4: Verify diagnostics are unchanged**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/refine-oracle.sh check /tmp/refine-base-$SLUG; echo "refine_exit=$?"
scripts/run-tests.sh compiler; echo "suite_exit=$?"
```

Expected: both exit 0. A diagnostic-text change here would also break the CI-only `@types-check` alias, which asserts on exact message text.

- [ ] **Step 5: Commit**

```bash
git add lib/refinecheck/refine_check.ml && git commit -m "refactor(refinecheck): bundle check_call's traversal-constant params into a record"
```

### Task 3.4: Add `refine_check.mli`

**Files:** Create `lib/refinecheck/refine_check.mli`; modify `lib/refinecheck/dune` if needed (`.mli` files do not need a `(modules …)` entry — the `.ml` already has one).

- [ ] **Step 1: Find the actual public surface**

```bash
grep -rhoE '\bRefine_check\.[a-z_][a-zA-Z0-9_]*' --include='*.ml' . | sort | uniq -c | sort -rn
```

- [ ] **Step 2: Write an `.mli` exporting only those names**

Do not export all 197 definitions. If the externally-used set is small (likely under 10), the `.mli` is the single most valuable artifact in this phase: it turns "197 top-level lets" into a readable API.

- [ ] **Step 3: Build, verify, commit**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/refine-oracle.sh check /tmp/refine-base-$SLUG && scripts/run-tests.sh compiler; echo "exit=$?"
git add lib/refinecheck/refine_check.mli && git commit -m "refactor(refinecheck): add refine_check.mli documenting the public API"
```

---

## Phase 4 — `analysis.ml`: split the code-action engines

**[verified 2026-08-25]** — `lsp/lib/analysis.ml` is untouched by the perf project: still 8,132 lines, `ast_code_actions` at `:5675`, `code_actions_at` at `:6764`, composition at `:7755`. Every number in this phase re-measured correct.

**These two functions are NOT duplicates** — verified: `ast_code_actions` is called exactly once, at `analysis.ml:7755`, appended to `code_actions_at`'s result, and their action-title sets do not intersect. They are complementary engines (AST-driven refactorings vs diagnostic-driven quick fixes) that happen to share a file. This is a plain split.

### Task 4.1: Move both engines to their own modules

**Files:**
- Create: `lsp/lib/code_actions_ast.ml` (from `analysis.ml:5675–6763`)
- Create: `lsp/lib/code_actions_diag.ml` (from `analysis.ml:6764–7760`)
- Modify: `lsp/lib/analysis.ml`
- `lsp/lib/dune` has **no** `(modules …)` field — new files are picked up automatically. Nothing to edit.

**Interfaces:**
- Produces: `Code_actions_ast.actions : Analysis.t -> line:int -> character:int -> Lsp.Types.CodeAction.t list` and `Code_actions_diag.actions : Analysis.t -> line:int -> character:int -> diagnostics:Lsp.Types.Diagnostic.t list -> Lsp.Types.CodeAction.t list` (the diagnostic engine consumes the pushed diagnostics; the AST engine never did). `Analysis.code_actions_at` keeps its **exact** current signature — `~line ~character ?(diagnostics = []) ()`, trailing unit included — and becomes a composition. It has 9+ call sites in `lsp/test/test_lsp.ml` passing `()` that must not change.

- [ ] **Step 1: Confirm the boundaries and the composition point**

```bash
grep -n '^let ast_code_actions\|^let code_actions_at\|ast_code_actions a ~line' lsp/lib/analysis.ml
```

Expected: definitions at 5675 and 6764, composition at 7755.

- [ ] **Step 2: Check for a circular dependency**

Both engines take `Analysis.t`. If `t` is defined in `analysis.ml`, the new modules cannot `open Analysis` without a cycle. Check:

```bash
grep -n '^type t = \|^and t = ' lsp/lib/analysis.ml | head
```

If `t` lives in `analysis.ml`, extract it to `lsp/lib/analysis_types.ml` **first**, as its own commit, before moving either engine. Do not attempt both in one step.

- [ ] **Step 3: Move `code_actions_ast.ml`, build, test**

```bash
dune build --root . lsp/ 2>&1 | tail -5 && dune build --root . lsp/test/test_lsp.exe && ./_build/default/lsp/test/test_lsp.exe -e 2>&1 | tail -5; echo "exit=$?"
```

- [ ] **Step 4: Commit, then repeat for `code_actions_diag.ml`**

```bash
git add lsp/lib/code_actions_ast.ml lsp/lib/analysis.ml && git commit -m "refactor(lsp): extract AST-driven code actions to code_actions_ast.ml"
```

- [ ] **Step 5: Reduce `code_actions_at` to a composition and commit**

The signature below is copied from `analysis.ml:6764-6767`. The `?diagnostics` default and the trailing `()` are load-bearing — every `test_lsp.ml` call site passes `()` and the server passes `~diagnostics`. Dropping either breaks the API.

```ocaml
let code_actions_at (a : t) ~line ~character
    ?(diagnostics : Lsp.Types.Diagnostic.t list = [])
    ()
    : Lsp.Types.CodeAction.t list =
  Code_actions_diag.actions a ~line ~character ~diagnostics
  @ Code_actions_ast.actions a ~line ~character
```

Order matters — diagnostic actions came first in the original. Verify against `analysis.ml:7755` before writing.

---

## Phase 5 — `bin/main.ml`: one CAS-key site, not two

**[corrected 2026-08-25]** — `bin/main.ml` is **5,402** lines (the draft said 5,162): `--jit` mode (#344), the stdlib typecheck-env cache (#342) and #347 landed in between. `compile` is **2,510** lines (`:2298–4807`, was "2,360"), and the second `cas_flags` site moved.

`compile` is 2,510 lines, but linear driver code is the *friendliest* shape to work in — no hidden coupling, read the window you need. This phase does **not** split it. It fixes one thing: `cas_flags` is constructed at **two** sites (**`main.ml:2401`** and **`main.ml:3781`**, was :2325 / :3606), and a codegen flag added to one and not the other silently produces cache hits across semantically different builds.

Derive both, never paste them:

```bash
grep -n 'let cas_flags' bin/main.ml            # 2401, 3781
grep -n 'MARCH_DEBUG_CASFLAGS' bin/main.ml     # 3800 (site 2 only)
```

### Task 5.1: Extract `cas_flags` construction

**Files:** Modify `bin/main.ml`

- [ ] **Step 1: Diff the two sites**

```bash
A=$(grep -n 'let cas_flags' bin/main.ml | sed -n 1p | cut -d: -f1)
B=$(grep -n 'let cas_flags' bin/main.ml | sed -n 2p | cut -d: -f1)
diff <(sed -n "${A},$((A+22))p" bin/main.ml) <(sed -n "${B},$((B+22))p" bin/main.ml)
```

Record every difference. Some are legitimate (the second site adds sysroot `.so` digests per the comment just above it at **:3770**, was :3595); those become parameters, not divergence.

- [ ] **Step 2: Write a single constructor above both sites**

```ocaml
(** Build the CAS cache-key flag list.  THE only place codegen flags enter the
    cache key.  A flag that affects emitted code but is missing here makes two
    semantically different builds collide on one cache entry — the failure is a
    silently stale binary, not an error.

    [extra] carries site-specific digests (e.g. sysroot .so hashes on the
    cross-compile path); everything else is shared by every call site. *)
let build_cas_flags ~(extra : string list) : string list =
  (* body: the union of the two current sites, with their differences reduced
     to [extra].  Copy verbatim from main.ml:2325 and :3606 — do not retype. *)
```

Move the existing `MARCH_DEBUG_CASFLAGS` debug print (**`main.ml:3800-3802`**, was :3625-3627) **into** this function so that every call site logs its flag list identically — that print is what Step 3 verifies against.

- [ ] **Step 3: Prove the flag LIST is unchanged — never compare cache keys across compiler builds**

The CAS key includes the digest of the compiler executable itself. Any comparison that spans "rebuild the compiler" therefore **always** yields different keys — an artifact-count check is structurally incapable of validating this refactor, and a naive reading of its inevitable failure invites a wrong "fix". Compare the flag *list* instead.

Site 2 (**`main.ml:3800`**) already has an env-gated print; site 1 (**`:2419`**, the `let ch = … compilation_hash …` line — was :2343) has none. So first, as a print-only preparatory change, copy the same three-line `eprintf` to site 1, directly after its `let ch = … compilation_hash …` line. A print cannot alter the key. Build and capture the "before" flag lists with a flag that must be key-distinct (`--cap-strict`) in one run and not the other:

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
# [corrected 2026-08-25] the draft's one-liner does not compile: March requires a
# module wrapper AND a capability grant, so it died in the typechecker and the
# probe printed nothing — a vacuous capture that reads exactly like a real result.
printf 'mod Main do\n  needs IO\n  fn main(cap : Cap(IO)) do\n    println("cas-probe")\n  end\nend\n' > /tmp/cas-probe-$SLUG.march
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile -o /tmp/cas-probe-$SLUG.bin /tmp/cas-probe-$SLUG.march > /tmp/casflags-before-a-$SLUG.log 2>&1
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile --cap-strict -o /tmp/cas-probe-$SLUG.bin /tmp/cas-probe-$SLUG.march > /tmp/casflags-before-b-$SLUG.log 2>&1
grep -c MARCH_CASFLAGS /tmp/casflags-before-a-$SLUG.log /tmp/casflags-before-b-$SLUG.log
```

Expected: **non-zero** counts for both. A zero means the probe did not reach a printing site — the capture is vacuous; do not proceed until it prints.

Now apply the Step-2 refactor (the print moves into `build_cas_flags`), rebuild, recapture, and diff the flag lists only:

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile -o /tmp/cas-probe-$SLUG.bin /tmp/cas-probe-$SLUG.march > /tmp/casflags-after-a-$SLUG.log 2>&1
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile --cap-strict -o /tmp/cas-probe-$SLUG.bin /tmp/cas-probe-$SLUG.march > /tmp/casflags-after-b-$SLUG.log 2>&1
diff <(grep -o 'flags=\[[^]]*\]' /tmp/casflags-before-a-$SLUG.log) <(grep -o 'flags=\[[^]]*\]' /tmp/casflags-after-a-$SLUG.log); echo "a_exit=$?"
diff <(grep -o 'flags=\[[^]]*\]' /tmp/casflags-before-b-$SLUG.log) <(grep -o 'flags=\[[^]]*\]' /tmp/casflags-after-b-$SLUG.log); echo "b_exit=$?"
```

Expected: `a_exit=0` and `b_exit=0` — the flag lists are byte-identical, so the key is unchanged for any fixed compiler binary. The `ch=` hashes in the before/after logs **will** differ because the compiler was rebuilt between captures; that is the compiler-digest component doing its job, not a regression. Also confirm the `b` list contains `capstrict` and the `a` list does not — otherwise the probe is not exercising flag-sensitivity.

- [ ] **Step 4: Verify and commit**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG && scripts/run-tests.sh codegen; echo "exit=$?"
git add bin/main.ml && git commit -m "refactor(main): construct CAS cache-key flags in exactly one place"
```

---

## Phase 6 — `typecheck.ml`: cold data only (DOWNSCOPED)

**[corrected 2026-08-25]** — `typecheck.ml` is **14,957** lines (was 14,908) and `infer_expr` is **1,500** lines at `:5724–7223` (was "1,473"). `builtin_cap_table` is at **`typecheck.ml:1967`**, not `~1025`.

Done last, deliberately. This is the **best-decomposed** file in the set (223 top-level definitions, 21 § sections, largest function only 10% of the file) and the **most contended** (34 of the last 300 commits). Every line moved here is a rebase risk for concurrent work.

**Downscoped at review (2026-08-23).** The first draft extracted `builtin_bindings` and `pp_ty`. Both are coupled to the `ty`/`scheme` types defined *inside* `typecheck.ml` — measured: the `builtin_bindings` range uses `TArrow` ×956, `TCon` ×539, `Mono` ×451, plus `Poly`/`TTuple`/`TVar`; `pp_ty` pretty-prints `ty` and reads the `_tvar_names`/`_record_names` tables. Extracting either therefore requires *first* extracting the core type definitions to a `typecheck_types.ml` — a structural change to the hottest file in the repo, for a navigation win its 21 § headers already mostly deliver. The earlier "zero coupling" claim checked only for calls into the inference core and missed the type constructors; it was wrong. Not worth the rebase risk now. If a `typecheck_types.ml` ever exists for other reasons, revisit both extractions. Verification recipe for that day: the IR oracle, the full suite, **and** `dune build @types-check --force` judged by its log contents — `pp_ty` feeds diagnostic text, that CI-only alias asserts exact message strings, and without `--force` it exits 0 with a zero-byte log (vacuous).

What remains in scope is the one genuinely uncoupled item.

`lib/typecheck/dune` has no `(modules …)` field — new files are picked up automatically.

### Task 6.1: Extract `builtin_cap_table`

`builtin_cap_table` is a **115**-line pure `(string * string) list` literal (`typecheck.ml:1967–2081` at `8d2b22fb`) — no `ty`, no `scheme`, no helper calls. **[corrected 2026-08-25]** — the draft said "140-line" at `~1025`; the coupling premise re-checked clean (the Step-1 grep prints **0**).

**Files:**
- Create: `lib/typecheck/builtin_caps.ml`
- Modify: `lib/typecheck/typecheck.ml`

**Interfaces:**
- Produces: `Builtin_caps.table : (string * string) list`. `typecheck.ml` keeps `let builtin_cap_table = Builtin_caps.table` at the original position so no other line in the file changes.

- [ ] **Step 1: Confirm zero type coupling before moving**

```bash
S=$(grep -n '^let builtin_cap_table' lib/typecheck/typecheck.ml | cut -d: -f1)
E=$(awk -v s=$S 'NR>s && /^\]/{print NR; exit}' lib/typecheck/typecheck.ml)
echo "table = $S..$E"      # 1967..2081 at 8d2b22fb
sed -n "${S},${E}p" lib/typecheck/typecheck.ml | grep -cE '\b(Mono|Poly|TArrow|TCon|TVar|TTuple|scheme)\b'
```

Expected: **0**. Non-zero means the premise changed since `1f5a0111` — stop and report rather than extracting.

- [ ] **Step 2: Move the table verbatim, re-export**

```bash
E=$(awk -v s=$S 'NR>s && /^\]/{print NR; exit}' lib/typecheck/typecheck.ml)
{ echo '(** Builtin capability table — which builtin requires which capability.'
  echo '    Pure data; extracted verbatim from typecheck.ml.  No behavior change. *)'
  echo
  sed -n "${S},${E}p" lib/typecheck/typecheck.ml | sed '1s/^let builtin_cap_table/let table/'
} > lib/typecheck/builtin_caps.ml
```

Then replace lines `S`–`E` in `typecheck.ml` with `let builtin_cap_table = Builtin_caps.table`, keeping the original doc comment above it.

- [ ] **Step 3: Verify and commit**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-$SLUG; echo "ir_exit=$?"
scripts/run-tests.sh compiler eval; echo "suite_exit=$?"
git add lib/typecheck/builtin_caps.ml lib/typecheck/typecheck.ml && git commit -m "refactor(typecheck): extract builtin_cap_table to builtin_caps.ml"
```

---

## Phase 7 — Close the books

### Task 7.1: Update the canonical records

**Files:**
- Modify: `CHANGELOG.md`
- Move: `specs/todos/2026-08-19-compiler-file-decomposition.md` → `specs/progress/`
- Modify: `CLAUDE.md` (the `lib/tir/` project-layout line now lists new modules)

- [ ] **Step 1: Re-measure and record the result**

```bash
wc -l lib/typecheck/typecheck.ml lib/eval/eval.ml lsp/lib/analysis.ml lib/refinecheck/refine_check.ml lib/tir/llvm_emit.ml bin/main.ml | sort -rn
```

Put the before/after table in the `specs/progress/` entry.

- [ ] **Step 2: Update `CLAUDE.md`'s project-layout block**

The `lib/tir/` line must name `builtin_name`, `llvm_emit_arith`, `llvm_emit_task`, `llvm_emit_record`; the `lib/eval/` entry must reflect the split. `scripts/check-docs.sh` lints current-truth docs for dead compiler-source pointers, so a stale layout line will fail CI.

- [ ] **Step 3: Run the doc lint**

```bash
scripts/check-docs.sh > /tmp/doclint-$SLUG.log 2>&1; echo "exit=$?"; tail -20 /tmp/doclint-$SLUG.log
```

Note: doc-lint has been green locally and red in CI before, because CI tests the **merge ref**, not your tip. Before opening a PR: `git fetch origin && git merge origin/main` (never bare `git merge main` — it merges a stale local ref), then re-run.

- [ ] **Step 4: Final full-suite verification**

```bash
scripts/run-tests.sh > /tmp/suite-final-$SLUG.log 2>&1; echo "exit=$?"
diff <(grep -oE '[0-9]+ (passed|failed)' /tmp/suite-base-$SLUG.log) <(grep -oE '[0-9]+ (passed|failed)' /tmp/suite-final-$SLUG.log)
```

Expected: exit 0 and an empty diff against the Phase 0 baseline.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md CLAUDE.md && git mv specs/todos/2026-08-19-compiler-file-decomposition.md specs/progress/ && git commit -m "docs: record compiler file decomposition and refresh project layout"
```

---

## Risks

**Rebase pressure is the dominant risk, and it was accepted deliberately.** `typecheck.ml` alone takes 34 of every 300 commits; `eval.ml`, `llvm_emit.ml`, and `main.ml` add another 44 between them. A single long-lived branch touching all six files will conflict with concurrent work. Mitigations built into the plan: every task is its own commit; phases are independent and can land separately; `typecheck.ml` (most contended) is last and touches least. If conflicts appear, land the completed phases and re-cut the branch rather than carrying the whole set.

**Codegen is where this repo's bugs hide.** Phase 2 touches the LLVM emitter, and the failure mode here is historically a *compiled-only* miscompile that interpreted tests never see. This is why Phase 2 asserts byte-identical IR at every batch rather than relying on the test suite, and why Task 2.2 Step 3 stops after a single converted arm.

**Vacuous green is the second-order risk.** Every oracle in this plan has a non-vacuousness guard (`emitted < 100`, `report_lines < 50`) and a step that proves it fires (Task 0.1 Step 3). Do not remove them. A "tests pass" claim from a stale `_build`, a warm CAS, or a `@types-check` without `--force` is worth nothing.

**Parallel agents share this worktree.** A torn read looks exactly like a real regression. If an oracle fails inexplicably, check `git status` and `ps` for concurrent work before diagnosing the code.

## Self-review

- **Coverage:** all six files from the measured baseline have at least one task; `desugar.ml` and `test_lsp.ml` are explicitly listed as out of scope with reasons.
- **Signature consistency:** `Builtin_name.of_string`/`to_string`/`all` are used with the same names in Tasks 2.1, 2.2, 2.3 and the round-trip test. `Eval_builtins.base_env` in Task 1.3 matches the `.mli` in the same task and the re-export in Step 5.
- **Resolved during review:** the plan initially hedged on whether `value`/`env` lived in a shared `Eval_types`. Checked: they do not — `type value` is at `eval.ml:32`, `and env` at `:141`. That hedge is now Task 1.0, a hard prerequisite with its own commit, and the dependent steps in Tasks 1.1 and 1.3 state exact types instead of fallbacks.
- **Verified, not assumed:** warning 8 (`partial-match`) is a *build error* under dune's default dev profile — tested with a scratch project, not inferred. Task 2.2's exhaustiveness guarantee depends on this.
- **Line numbers drift — and they did.** Every task after the first move in its file re-locates its boundary by `grep` rather than trusting a number from this document. **[corrected 2026-08-25]** the draft's closing line ("Line numbers here are from `1f5a0111`") understated the hazard: the numbers were *also* used as the primary bounds for the FIRST move in each file, where nothing re-derived them. That is why the 2026-08-25 pass replaced them with `grep`/`awk` derivations wherever a stable textual anchor exists, and why the surviving literals are tagged **[verified]** rather than left bare. A `sed`-based extraction against a wrong range does not fail — it silently mangles code.

## Re-anchoring pass (2026-08-25, at `8d2b22fb`)

Recorded here so a later reader knows what was checked, not merely what was changed.

**Corrected (the stated fact was false):** the Measured Baseline table (`llvm_emit.ml`, `bin/main.ml`, `eval.ml`, `typecheck.ml` line counts and largest-def sizes); `base_env`'s end (`9393` → `9510`) and size (`5,187` → `5,274`) and entry count (`590` → `595`); `Eval.base_env` call sites (`27` → `28`); the corpus size (`227` → `243`, `240` emitting); the builtin-name count (`50`/`58` → `57`) and the claim that `root_cap` is one of them (it is dispatched in `emit_atom`, not `emit_expr`); the claim that `task_await` has two emit arms (it has one); the entire Phase-2 arm line-number set (~+126 each); both `cas_flags` sites and the `MARCH_DEBUG_CASFLAGS` print; `builtin_cap_table`'s position (`~1025` → `1967`) and size (`140` → `115`); Task 1.1's block end (`4206` → `4205`, an off-by-one into the next section's header rule); the Phase-5 probe program, which never compiled; and `scripts/ir-oracle.sh`'s `${1:?…}` usage strings, which made the script exit before doing anything.

**Verified unchanged:** the Task 1.0 type block (`17–142`, no interleaved `let`); `Eval_types` still does not exist; all five hook refs and `Eval_error`/`eval_error` line numbers; the simd/net/session section anchors; `eval.ml:3496`'s http ordering constraint; `eval.ml:2249`'s `spawn_child_actor` hook call; the `Actor runtime`/`Dynamic Supervisor state`/`Monitors` section lines; all of Phase 3 (`refine_check.ml` 7,416 lines, `check_call` `:3371–4731`, three call sites); all of Phase 4 (`analysis.ml` 8,132 lines, `:5675`/`:6764`/`:7755`); the `--emit-llvm`-bypasses-CAS design, re-proved structurally and empirically; and IR determinism across differently-named source copies.

**Added:** Task 0.3 (interpreter-performance baseline) and Task 1.5 (Phase 1's exit gate), because the IR oracle is structurally blind to the interpreter — the one file Phase 1 exists to dismantle.

**Post-merge re-check.** After this pass, `origin/main` `7f91ea5d` (#347) was merged in. It
touched `bin/main.ml` (+12 lines), so all Phase-5 numbers above are stated **post-merge**;
`llvm_emit.ml`, `eval.ml`, `typecheck.ml`, `refine_check.ml` and `analysis.ml` were
untouched by it, and `scripts/ir-oracle.sh check` came back `IR IDENTICAL across 240
programs` on the merge — the oracle's first real use, confirming the merge changed no
emitted code. That `bin/main.ml` moved *again* inside a single day is the argument for the
`grep` derivations: a plan that hard-codes line numbers into this repo is stale before it
is executed.

## Review revisions (2026-08-23)

A verification pass against the codebase — checking the plan's load-bearing claims rather than its prose — found five defects in the first draft. All are fixed inline above; they are recorded here so an executing agent understands *why* the structure looks the way it does, and does not "simplify" it back into a bug.

1. **Module cycle in Phase 1 (critical — would not compile).** Every extraction block referenced `eval_error` (base_env ×717, session ×10, net ×4, simd ×1) and the hook refs (base_env ×41, net ×4), all of which the first draft left in `eval.ml`. Since `eval.ml` depends on the extracted modules, that is a cycle. The draft's "leaf check" also tested the wrong direction (references *below* the block, when the real rule is references to *anything remaining in `eval.ml`*). Fixes: new Task 1.0b (`eval_prim.ml`); Task 1.3 rewritten as a shared/exclusive split with `eval_runtime.ml` (27 shared helpers measured, 85 exclusive); dependency-check criteria corrected in Tasks 1.1–1.2.
2. **Phase 6 downscoped (critical — would not compile).** `builtin_bindings` uses `TArrow` ×956 / `TCon` ×539 / `Mono` ×451; `pp_ty` prints `ty`. Both need the type definitions extracted first, in the most contended file. The draft's "zero coupling" verification only looked for calls into the inference core. Dropped; only the genuinely uncoupled `builtin_cap_table` remains.
3. **`check_call` has three call sites** (`:5695`, `:5719`, `:5731`), not one — the draft's grep was `head`-truncated. Task 3.3's classification and threading corrected.
4. **`code_actions_at` signature.** The draft's composition dropped `?(diagnostics = [])` and the trailing `()`, which would break every `test_lsp.ml` call site and the server. Now preserved verbatim.
5. **Phase 5 verification method was structurally unable to pass.** The CAS key includes the compiler's own digest, so comparing keys across two compiler builds always differs. Replaced the artifact-count comparison with a `MARCH_DEBUG_CASFLAGS` flag-list diff; that env-gated print already existed at `main.ml:3625` and now lives inside `build_cas_flags` so both sites log.

Also hardened **Task 2.2**: the consolidated dispatch arm changes fall-through semantics (shape-mismatched calls previously fell through to the generic-app arms), so `emit_builtin` factors the generic arm into `emit_generic_app` and keeps it as each constructor's inner-match escape while the outer constructor match stays exhaustive. Placement wording corrected: the first *in-variant* arm is `not` at `:1853`; the `"&&"`/`"||"` string guards above it are not in the variant. And **Task 3.1** now states the refine oracle's multi-minute runtime so a baseline is not killed mid-run.

Verified and unchanged by the review: the IR oracle design and its determinism; warning 8 as a build error; the Task 1.0 type-block boundary (17–142, no interleaved `let`); the `analysis.ml` non-duplication finding; the 50-name builtin list.
