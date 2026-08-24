# Compiler File Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the six largest compiler files searchable, editable, and maintainable by extracting cold bulk into focused modules and converting string-keyed multi-site dispatch into compiler-checked variants.

**Architecture:** Two kinds of change, kept in **separate commits and never mixed**. (1) *Code motion* — definitions move verbatim into new modules; correctness is proven by byte-identical LLVM IR across a 227-program corpus. (2) *Semantic hardening* — string-guard dispatch becomes a variant, parameter floods become records; the IR legitimately changes, so proof is the test suite plus deliberate IR diff review. Phase 0 builds the oracle both kinds rely on; nothing else starts until it is green.

**Tech Stack:** OCaml 5.3.0 (opam switch `march`), dune 3.x, menhir, LLVM textual IR, alcotest.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **opam switch is `march`; `dune` and `opam` are already on PATH. NEVER prefix a command with `eval $(opam env …)`.**
- Run tests with `scripts/run-tests.sh`, **not** `dune runtest` (stale RPC daemon silently serves cached results). Judge success by `$?`, never by tail output, and never measure an exit code through a pipe.
- Never pipe `march --compile` — it hangs. Redirect to a file.
- `git add` explicit paths only. Never `git add -A`, `git add .`, `git add *`, or `git commit -am`.
- **Never `git stash` in this worktree** — the stash stack is shared across all march worktrees. Use a file copy to park changes.
- No `Co-Authored-By` trailers.
- **`lib/tir/dune` and `lib/refinecheck/dune` carry explicit `(modules …)` lists.** A new module in either directory is *silently not compiled* until it is added to that list. Add it in the same commit that creates the file. `lib/typecheck`, `lib/eval` (`(:standard \ discover_compress)`), and `lsp/lib` use default discovery — nothing to edit there.
- Before trusting any "pre-existing failure", rebuild fully: a targeted `dune build bin/main.exe` does **not** refresh `_build`'s staged copies of `stdlib/` and `runtime/`, which manufactures fake failures.
- Per CLAUDE.md: when a task closes a `specs/todos/` item, `git mv` it to `specs/progress/` in the same commit. Pure-refactor commits with no user-visible behavior change do **not** get a `CHANGELOG.md` bullet; Phase 2 and Phase 3 hardening *do* (they change diagnostics/codegen structure).

---

## Measured Baseline

The numbers this plan is built on, measured at `1f5a0111`:

| File | Lines | Largest single def | % of file | § headers | `.mli` | Commits (last 300) |
|---|---|---|---|---|---|---|
| `lib/tir/llvm_emit.ml` | 5,255 | `emit_expr` 3,985 | **76%** | 0 | no | 16 |
| `bin/main.ml` | 5,162 | `compile` 2,360 | 46% | 10 | no | 11 |
| `lib/eval/eval.ml` | 12,112 | `base_env` 5,187 | 43% | 70 | no | 17 |
| `lsp/lib/analysis.ml` | 8,132 | 3 fns ≈3,000 | 37% | 49 | no | — |
| `lib/desugar/desugar.ml` | 3,320 | `derive_impl` 942 | 28% | 8 | no | 5 |
| `lib/refinecheck/refine_check.ml` | 7,416 | `check_call` 1,361 | 18% | **0** | no | — |
| `lib/typecheck/typecheck.ml` | 14,908 | `infer_expr` 1,473 | **10%** | 21 | no | **34** |

**`typecheck.ml` is the best-decomposed file of the set** — longest, but most evenly divided. It is therefore *last* in this plan, not first. Length is not the problem; a 4,000-line single function is.

**Correction to an earlier hypothesis:** `analysis.ml`'s two ~1,000-line code-action functions were suspected duplicates. They are not. `ast_code_actions` is called exactly once, at `analysis.ml:7755`, appended to `code_actions_at`'s result, and their action-title sets do not intersect. They are complementary (diagnostic-driven vs AST-driven). Phase 4 is therefore a plain split, not a dedup.

---

## The Verification Oracle

`--emit-llvm` writes `<file>.ll` and exits **before** the CAS cache path, so it cannot be short-circuited by a warm cache. Empirically verified at `1f5a0111`: output is byte-identical across repeated runs **and** across differently-named copies of the same source (0 diff lines) — no source path, timestamp, or UUID is baked in.

This makes IR hashing a sound oracle for code motion. It is the linchpin of the plan: a task that claims "I only moved code" must *prove* it, because this repo has a documented history of vacuous-green results (stale `_build` staging, warm-CAS short-circuit, skip-on-compile-failure).

Corpus: 165 `test/native/*.march` + 16 `test/snapshots/src/*.march` + 46 `bench/*.march` = **227 programs**.

---

## File Structure

New files created by this plan. Each has one responsibility; files that change together live together.

| New file | Responsibility | Extracted from | Approx. lines |
|---|---|---|---|
| `scripts/ir-oracle.sh` | Hash LLVM IR for the 227-program corpus; compare against a saved baseline | — | ~70 |
| `lib/eval/eval_types.ml` | Interpreter `value` / `env` type block (PREREQUISITE for all of Phase 1) | `eval.ml:17-142` | ~126 |
| `lib/eval/eval_prim.ml` | `Eval_error` + `eval_error` + late-bound hook refs — the bottom layer that breaks the extraction cycle | `eval.ml:1096/:1239/:1520/:1814-1824` | ~40 |
| `lib/eval/eval_runtime.ml` | Shared runtime state: actor registry, scheduler entry, type tables, timers, vault registry | `eval.ml` (scattered; Task 1.3 Step 0 lists it) | ~450 |
| `lib/eval/eval_simd.ml` | Simd 128-bit vector ops + NativeArray narrow-width (f32/i32/u8) helpers | `eval.ml:4054–4206` | ~150 |
| `lib/eval/eval_net.ml` | CSV parser, HTTP server, WebSocket, non-blocking connection multiplexer | `eval.ml:2691–3861` | ~1,170 |
| `lib/eval/eval_session.ml` | Session-typed channel runtime + MPST runtime | `eval.ml:3862–3987` | ~125 |
| `lib/eval/eval_builtins.ml` | `base_env` (590 entries) plus its ~85 table-exclusive helpers | `eval.ml:4207–9393` + scattered | ~5,600 |
| `lib/eval/eval_builtins.mli` | Interface: `val base_env : Eval_types.env` | — | ~5 |
| `lib/tir/builtin_name.ml` | `Builtin_name.t` variant + `of_string`/`to_string` for the 50 codegen-dispatched builtins | — | ~140 |
| `lib/tir/builtin_name.mli` | Interface | — | ~15 |
| `lib/tir/llvm_emit_arith.ml` | Int/float arithmetic, comparison, bitwise arms | `llvm_emit.ml` | ~700 |
| `lib/tir/llvm_emit_task.ml` | task_*, actor, signal, channel, MPST arms | `llvm_emit.ml` | ~900 |
| `lib/tir/llvm_emit_record.ml` | record_*, vault_*, html_*, to_string arms | `llvm_emit.ml` | ~800 |
| `lib/refinecheck/refine_check.mli` | Public API of the refinement checker | — | ~40 |
| `lib/typecheck/builtin_caps.ml` | `builtin_cap_table` — 140-line pure string-pair list | `typecheck.ml:~1025` | ~145 |
| `lsp/lib/code_actions_ast.ml` | AST-driven refactorings (pipe, extract, …) | `analysis.ml:5675–6763` | ~1,090 |
| `lsp/lib/code_actions_diag.ml` | Diagnostic-driven quick fixes | `analysis.ml:6764–7760` | ~1,000 |

Files **not** touched: `lib/desugar/desugar.ml` (3,320 lines, 8 sections, largest def is a 942-line template-expander — healthy), `lsp/test/test_lsp.ml` (7,145 lines but 395 independent top-level tests and 177 headers — test files are the benign case).

**Precedent:** `test/test_ir_verify.ml`'s header comment already establishes this repo's convention — it was created as "a NEW file rather than growing test_codegen.ml (already ~6400 lines)". This plan applies that same judgment to `lib/`.

---

## Phase 0 — Build the oracle

Nothing else in this plan may start until Task 0.1 is committed and green. Every subsequent code-motion task depends on it.

### Task 0.1: IR hashing harness

**Files:**
- Create: `scripts/ir-oracle.sh`
- Create: `specs/todos/2026-08-19-compiler-file-decomposition.md` (tracking item for the whole plan)

**Interfaces:**
- Produces: `scripts/ir-oracle.sh baseline <dir>` writes one `.sha256` manifest; `scripts/ir-oracle.sh check <dir>` diffs current IR against it and exits non-zero on any mismatch. Every later task calls exactly these two subcommands.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# IR oracle — proves a refactor changed no emitted code.
#
# --emit-llvm writes <file>.ll and exits BEFORE the CAS cache path, so it
# cannot be short-circuited by a warm cache.  Output is byte-identical across
# runs and across differently-named copies of the same source (verified at
# 1f5a0111), so a plain sha256 over the .ll text is a sound oracle.
#
#   scripts/ir-oracle.sh baseline /tmp/ir-base   # record
#   scripts/ir-oracle.sh check    /tmp/ir-base   # compare
set -uo pipefail

MODE="${1:?usage: ir-oracle.sh {baseline|check} <dir>}"
DIR="${2:?usage: ir-oracle.sh {baseline|check} <dir>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="$ROOT/_build/default/bin/main.exe"
WORK="$DIR/work"
MANIFEST="$DIR/ir.sha256"

[ -x "$EXE" ] || { echo "FATAL: $EXE not built. Run: dune build bin/main.exe"; exit 2; }

mkdir -p "$WORK"
: > "$WORK/manifest.tmp"
skipped=0; emitted=0

for f in "$ROOT"/test/native/*.march "$ROOT"/test/snapshots/src/*.march "$ROOT"/bench/*.march; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .march)"
  # Namespace by parent dir: basenames collide across the three corpora.
  tag="$(basename "$(dirname "$f")")_$base"
  cp "$f" "$WORK/$tag.march"
  if "$EXE" --emit-llvm "$WORK/$tag.march" >"$WORK/$tag.log" 2>&1 && [ -f "$WORK/$tag.ll" ]; then
    printf '%s  %s\n' "$(shasum -a 256 <"$WORK/$tag.ll" | cut -d' ' -f1)" "$tag" >> "$WORK/manifest.tmp"
    emitted=$((emitted+1))
  else
    # A fixture that does not compile is EXPECTED for some corpus entries
    # (ill-typed negative tests).  Record it as a skip WITH its reason so a
    # refactor that newly breaks a previously-emitting fixture shows up as a
    # manifest line disappearing, not as a silent pass.
    printf 'SKIP  %s\n' "$tag" >> "$WORK/manifest.tmp"
    skipped=$((skipped+1))
  fi
done

sort "$WORK/manifest.tmp" > "$WORK/manifest.sorted"
echo "emitted=$emitted skipped=$skipped"

if [ "$emitted" -lt 100 ]; then
  echo "FATAL: only $emitted fixtures emitted IR — the corpus is not being"
  echo "exercised (stale build? wrong exe?).  Refusing to record a vacuous"
  echo "baseline."
  exit 2
fi

case "$MODE" in
  baseline)
    cp "$WORK/manifest.sorted" "$MANIFEST"
    echo "baseline recorded: $MANIFEST ($emitted programs)"
    ;;
  check)
    [ -f "$MANIFEST" ] || { echo "FATAL: no baseline at $MANIFEST"; exit 2; }
    if diff -u "$MANIFEST" "$WORK/manifest.sorted" > "$DIR/ir.diff"; then
      echo "IR IDENTICAL across $emitted programs"
      exit 0
    else
      echo "IR CHANGED — $(grep -c '^[+-][^+-]' "$DIR/ir.diff") differing lines:"
      head -40 "$DIR/ir.diff"
      echo "(full diff: $DIR/ir.diff)"
      exit 1
    fi
    ;;
  *) echo "unknown mode: $MODE"; exit 2 ;;
esac
```

- [ ] **Step 2: Make it executable and prove it is non-vacuous**

```bash
chmod +x scripts/ir-oracle.sh && dune build bin/main.exe && scripts/ir-oracle.sh baseline /tmp/ir-base-510e49
```

Expected: `emitted=` a number **≥ 100**. If it prints `FATAL: only N fixtures emitted`, stop — the build is stale or the exe is wrong. Do not proceed.

- [ ] **Step 3: Prove the oracle DETECTS a change (the critical step)**

An oracle that never fires is worthless. Introduce a deliberate one-character codegen change, confirm the oracle catches it, then revert:

```bash
sed -i.bak 's/let emit_atom ctx (atom : Tir.atom)/let emit_atom ctx (atom : Tir.atom) (* oracle-probe *)/' lib/tir/llvm_emit.ml && dune build bin/main.exe 2>&1 | tail -3
```

That comment-only edit should NOT change IR. Now make a real one:

```bash
grep -n 'int_max_value' lib/tir/llvm_emit.ml | head -2
```

Edit the `int_max_value` arm's emitted constant (e.g. `9223372036854775807` → `9223372036854775806`), rebuild, then:

```bash
scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "exit=$?"
```

Expected: `IR CHANGED`, `exit=1`, and the diff names the fixtures that use it.

- [ ] **Step 4: Revert the probe and confirm green**

```bash
git checkout lib/tir/llvm_emit.ml && rm -f lib/tir/llvm_emit.ml.bak && dune build bin/main.exe && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "exit=$?"
```

Expected: `IR IDENTICAL across N programs`, `exit=0`.

- [ ] **Step 5: Record the tracking todo**

Create `specs/todos/2026-08-19-compiler-file-decomposition.md`:

```markdown
# Compiler file decomposition

The six largest compiler files carry most of their mass in single giant
definitions (`emit_expr` 3,985 lines = 76% of llvm_emit.ml; `base_env` 5,187
lines = 43% of eval.ml).  Plan: specs/plans/2026-08-19-compiler-file-decomposition.md

Status: in progress.  Phase 0 (IR oracle) landed; phases 1-6 open.
```

- [ ] **Step 6: Commit**

```bash
git add scripts/ir-oracle.sh specs/plans/2026-08-19-compiler-file-decomposition.md specs/todos/2026-08-19-compiler-file-decomposition.md && git commit -m "test: add LLVM IR oracle for behavior-preserving refactors"
```

### Task 0.2: Record the full-suite baseline

**Files:** none modified — this task produces a recorded artifact only.

- [ ] **Step 1: Run the full suite and save the result**

```bash
scripts/run-tests.sh > /tmp/suite-base-510e49.log 2>&1; echo "exit=$?"; tail -20 /tmp/suite-base-510e49.log
```

- [ ] **Step 2: Record the pass/fail counts**

Note the per-suite counts in your working notes. **Any test already failing here is a pre-existing failure and is NOT this plan's to fix** — but it must be recorded now, because a failure discovered later without this baseline will be misattributed to the refactor.

- [ ] **Step 3: Record the TIR snapshot baseline**

```bash
dune build test/run_snapshots.exe && ./_build/default/test/run_snapshots.exe -e > /tmp/snap-base-510e49.log 2>&1; echo "exit=$?"
```

Expected: exit 0. TIR snapshots pin lowering/Perceus shape; the IR oracle pins final codegen. Phases 1 and 6 must leave **both** untouched.

---

## Phase 1 — `eval.ml`: 12,112 → ~4,900 lines

Highest ROI and lowest risk. `base_env` (5,187 lines, 590 entries) references `eval_expr`/`eval_decl` **zero times** — the dependency runs strictly one way. The cycle-breaking machinery already exists in the file: `iface_dispatch_hook` (:1520), `eval_expr_hook` (:1814), `run_scheduler_hook` (:1819), `apply_hook` (:1824). Extraction reuses that established pattern rather than inventing one.

**Ordering matters, and the invariant is directional:** every extraction leaves `eval.ml` depending on the new module, so extracted code may reference **nothing that remains in `eval.ml`** — not merely nothing below its own block. Tasks 1.0/1.0b lay the bottom layer (types, then errors + hooks); Tasks 1.1–1.2 extract the leaf helper clusters; Task 1.3 splits the shared runtime state from the builtin table and moves both.

### Task 1.0: Extract the value/env type block (PREREQUISITE)

**Verified prerequisite, not a hedge:** `Eval_types` does **not** exist today. `type value` is at `eval.ml:32` and `and env` at `eval.ml:141`, both inside `eval.ml`. Every later task in Phase 1 needs these types from a sibling module, so this task must land first.

The block is lines **17-142** (`Ring buffer type` through `and env`) and contains *only* type definitions — no `let` bindings — so it moves cleanly.

**Files:**
- Create: `lib/eval/eval_types.ml`
- Modify: `lib/eval/eval.ml`

**Interfaces:**
- Produces: `type value`, `and env = (string * value) list`, plus the mutually-recursive record types `chan_endpoint` (:85), `mpst_endpoint` (:99), `timer_entry` (:117) and the ring-buffer type at :17. All keep their current names and shapes verbatim.

- [ ] **Step 1: Confirm the block contains no value bindings**

```bash
awk 'NR>=17 && NR<=142' lib/eval/eval.ml | grep -nE '^\s*let '
```

Expected: **no output**. Any hit means a function is interleaved with the types and must stay behind.

- [ ] **Step 2: Move lines 17-142 verbatim**

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

- [ ] **Step 3: Re-export the types from `eval.ml`**

`Eval.value` and `Eval.env` are referenced across the compiler and test suite. Add at the top of `eval.ml`, where the block used to be:

```ocaml
(* Value and environment types moved to eval_types.ml.  Re-exported so
   [Eval.value] / [Eval.env] keep working for existing call sites. *)
include Eval_types
```

`include` (not `open`) is required — `open` would make the constructors visible inside `eval.ml` but would NOT re-export them to `Eval.*` consumers.

- [ ] **Step 4: Build and verify**

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "ir_exit=$?"
scripts/run-tests.sh eval; echo "suite_exit=$?"
```

Expected: both exit 0. `include` changes no runtime behavior, so IR must be identical.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Enumerate what must move — do not trust the list above**

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

- [ ] **Step 2: Write `eval_prim.ml`**

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

- [ ] **Step 3: Re-export from `eval.ml` at the original positions**

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

- [ ] **Step 4: Build, verify IR, run the eval suite**

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "ir_exit=$?"
scripts/run-tests.sh eval; echo "suite_exit=$?"
```

Expected: both exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval_prim.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract Eval_error and hook refs to eval_prim.ml"
```

### Task 1.1: Extract Simd + NativeArray narrow-width helpers

**Files:**
- Create: `lib/eval/eval_simd.ml`
- Modify: `lib/eval/eval.ml:4054–4206` (delete after moving)
- Test: `scripts/ir-oracle.sh` + `scripts/run-tests.sh eval`

**Interfaces:**
- Consumes: `Eval_types.value` (already a separate concern in `eval.ml`'s §Value type at :29 — if it is not yet its own module, keep the type in `eval.ml` and have `eval_simd.ml` take it as a functor-free direct dependency by placing `eval_simd.ml` *after* the value type; see Step 2).
- Produces: `simd_all`, `simd_any`, `simd_bounds_check`, `simd_first_set`, `simd_hfold`, `simd_select`, `simd_maxnum_f`, `simd_minnum_f`, `simd_f32_{and,or,xor,not,zero,allones,is_highbit}`, `simd_f64_{and,or,xor,not,zero,allones,is_highbit}`, `simd_i32_is_highbit`, `simd_i64_is_highbit`, `simd_u8_is_highbit`, `f32_round`, `fma32_single_round`, `i32_wrap`, `u8_wrap`. All keep their current signatures verbatim.

- [ ] **Step 1: Confirm the exact boundary before touching anything**

```bash
sed -n '4054,4058p;4115,4120p;4204,4208p' lib/eval/eval.ml
```

Expected: line 4054 opens the `NativeArray narrow-width helpers` comment, 4117 opens `Simd`, and 4207 opens `Base environment`. The block to move is **4054–4206 inclusive**.

- [ ] **Step 2: Check the block's upward dependencies**

```bash
sed -n '4054,4206p' lib/eval/eval.ml | grep -oE '\b[a-z_][a-z0-9_]{3,}\b' | sort -u > /tmp/simd-ids-510e49.txt
grep -oE '^let ([a-z_][a-z0-9_]*)' lib/eval/eval.ml | sed 's/^let //' | sort -u > /tmp/eval-defs-510e49.txt
comm -12 /tmp/simd-ids-510e49.txt /tmp/eval-defs-510e49.txt
```

The direction that matters: `eval.ml` will depend on `eval_simd`, so the block may reference **nothing that remains in `eval.ml`** — whether it is defined above or below the block is irrelevant. Every name the `comm` prints must resolve to `Eval_types` (Task 1.0) or `Eval_prim` (Task 1.0b). Measured at review: the block's only `eval.ml` dependency is `eval_error` ×1, which Task 1.0b already moved. If other names appear, they move with the block or the block stays — stop and report.

- [ ] **Step 3: Move the block verbatim**

```bash
{ echo '(** Simd 128-bit vector ops and NativeArray narrow-width (f32/i32/u8)'
  echo '    helpers.  Extracted verbatim from eval.ml:4054-4206 — no behavior'
  echo '    change.  See specs/plans/2026-08-19-compiler-file-decomposition.md *)'
  echo
  echo 'open Eval_types'
  echo
  sed -n '4054,4206p' lib/eval/eval.ml
} > lib/eval/eval_simd.ml
sed -i.bak '4054,4206d' lib/eval/eval.ml && rm lib/eval/eval.ml.bak
```

- [ ] **Step 4: Re-point the use sites**

`base_env` calls these unqualified. Add at the top of `eval.ml`, immediately after its existing `open` lines:

```ocaml
open Eval_simd
```

`open Eval_types` resolves because Task 1.0 created that module. If it does not compile, Task 1.0 was skipped — go back and land it first rather than working around it here.

- [ ] **Step 5: Build and verify IR is untouched**

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "exit=$?"
```

Expected: `IR IDENTICAL across N programs`, `exit=0`, with N matching the baseline exactly.

- [ ] **Step 6: Run the eval suite**

```bash
scripts/run-tests.sh eval; echo "exit=$?"
```

Expected: exit 0, same counts as `/tmp/suite-base-510e49.log`.

- [ ] **Step 7: Commit**

```bash
git add lib/eval/eval_simd.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract Simd and NativeArray narrow-width helpers"
```

### Task 1.2: Extract the network/protocol runtime cluster

**Files:**
- Create: `lib/eval/eval_net.ml` (CSV, HTTP server, WebSocket, non-blocking multiplexer — `eval.ml:2691–3861`)
- Create: `lib/eval/eval_session.ml` (session channels + MPST — `eval.ml:3862–3987`)
- Modify: `lib/eval/eval.ml`

**Interfaces:**
- Produces from `eval_net.ml`: `csv_open_impl`, `csv_next_row_impl`, `csv_close_impl`, `handle_http_connection`, `run_http_event_loop`, `tcp_send_all`, `ws_send_frame`, `ws_recv_frame`.
- Produces from `eval_session.ml`: `chan_new`, `chan_send`, `chan_recv`, `chan_close`, `mpst_new`, `mpst_send`, `mpst_recv`, `mpst_close`.

- [ ] **Step 1: Verify both blocks are leaves**

Run the Step-2 dependency check from Task 1.1 against ranges `2691,3861` and `3862,3987`. Same rule as Task 1.1: every dependency must resolve to `Eval_types`, `Eval_prim`, or `Eval_simd` — nothing may remain in `eval.ml`. Measured at review: net uses `eval_error` ×4 and hook refs ×4; session uses `eval_error` ×10 — all satisfied by `Eval_prim`.

Mind the reverse direction too: a helper defined *inside* these blocks that the rest of `eval.ml` still uses (e.g. `tcp_send_all`) must be re-exported (`let tcp_send_all = Eval_net.tcp_send_all`) or have its remaining uses qualified. The build names every such case — fix them, don't work around them.

Note the ordering constraint recorded in the file at `eval.ml:3496`: `handle_http_connection` is the blocking implementation and the non-blocking multiplexer below it references it. Keep both in `eval_net.ml`, in their current relative order.

- [ ] **Step 2: Move `eval_session.ml` first (the smaller, cleaner block)**

```bash
{ echo '(** Session-typed channel runtime and multi-party (MPST) runtime.'
  echo '    Extracted verbatim from eval.ml:3862-3987 — no behavior change. *)'
  echo
  sed -n '3862,3987p' lib/eval/eval.ml
} > lib/eval/eval_session.ml
sed -i.bak '3862,3987d' lib/eval/eval.ml && rm lib/eval/eval.ml.bak
dune build bin/main.exe 2>&1 | tail -5
```

- [ ] **Step 3: Verify, then commit separately**

```bash
scripts/ir-oracle.sh check /tmp/ir-base-510e49 && scripts/run-tests.sh eval; echo "exit=$?"
git add lib/eval/eval_session.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract session-typed and MPST channel runtimes"
```

- [ ] **Step 4: Move `eval_net.ml`**

Line numbers have shifted by the Step-2 deletion. Re-locate before cutting:

```bash
grep -n 'CSV parser state\|Session-typed channel runtime' lib/eval/eval.ml
```

Use the CSV line as the new start and the line before the session marker (now the `Show dispatch helper` section) as the end. Move that range with the same pattern as Step 2.

- [ ] **Step 5: Verify and commit**

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49 && scripts/run-tests.sh eval; echo "exit=$?"
git add lib/eval/eval_net.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract CSV, HTTP, and WebSocket interpreter runtimes"
```

### Task 1.3: Extract `base_env` — the 5,187-line builtin table

**Rewritten at review (2026-08-23):** the first draft assumed the table's ~120 helper dependencies could stay in `eval.ml`. They cannot — `eval.ml` will depend on `eval_builtins.ml`, so anything the table uses must live in a sibling module. This task is therefore **two extractions**: first the *shared* runtime-state cluster (used by both the table and the evaluator) into `eval_runtime.ml`; then the table plus its *table-exclusive* helpers into `eval_builtins.ml`.

**Files:**
- Create: `lib/eval/eval_runtime.ml`, `lib/eval/eval_builtins.ml`, `lib/eval/eval_builtins.mli`
- Modify: `lib/eval/eval.ml`

**Interfaces:**
- Consumes: `Eval_types`, `Eval_prim`, `Eval_simd`, `Eval_net`, `Eval_session`.
- Produces from `eval_runtime.ml`: the shared runtime state. Measured at review (27 names, regenerate in Step 0 — it drifts): `actor_registry`, `impl_tbl`, `run_scheduler`, `ctor_type_tbl`, `type_name_of_value`, `next_pid`, `current_pid`, `named_registry`, `ffi_type_decl_tbl`, `shutdown_requested`, `record_type_tbl`, `pending_timers`, `vault_num_stripes`, `vault_registry`, `spawn_child_actor`, `timer_service_tick`, `dropped_messages_count`, `mailbox_enqueue`, `base64_decode`, `revocation_table`, `protocol_roles_tbl`, `logger_level`.
- Produces from `eval_builtins.ml`: `val base_env : Eval_types.env` — the **only** export; the ~85 exclusive helpers are internal.
- **`Eval.base_env` has 27 external call sites** (distinct from `Typecheck.base_env`, which also exists and is unrelated). `eval.ml` MUST keep `let base_env = Eval_builtins.base_env`.

- [ ] **Step 0: Classify the table's helper dependencies as shared or exclusive**

```bash
S=$(grep -n '^let base_env : env' lib/eval/eval.ml | cut -d: -f1)
E=$(grep -n '(\* Evaluation' lib/eval/eval.ml | cut -d: -f1)
awk -v s=$S -v e=$E 'NR>=s && NR<e' lib/eval/eval.ml | grep -oE '\b[a-z_][a-z0-9_]{3,}\b' | sort -u > /tmp/be-ids-510e49.txt
grep -oE '^let ([a-z_][a-z0-9_]*)' lib/eval/eval.ml | sed 's/^let //' | sort -u > /tmp/eval-defs-510e49.txt
awk -v s=$S -v e=$E 'NR<s || NR>=e' lib/eval/eval.ml > /tmp/eval-outside-510e49.txt
while read n; do echo "$(grep -cE "\b$n\b" /tmp/eval-outside-510e49.txt) $n"; done \
  < <(comm -12 /tmp/be-ids-510e49.txt /tmp/eval-defs-510e49.txt) | sort -rn
```

The number is how often the name appears in `eval.ml` *outside* the table. **≥ 3** (its definition plus real uses) → SHARED → `eval_runtime.ml`. **≤ 2** → table-EXCLUSIVE → moves *with* the table. Names already owned by `Eval_simd`/`Eval_net`/`Eval_session` (e.g. `f32_round`, `tcp_send_all`, `chan_*`, `csv_*`) are already siblings and need nothing.

The threshold is a starting classification, not an oracle. **The build is the arbiter:** an "exclusive" helper that `dune build` then reports missing from `eval.ml` was actually shared — move it to `eval_runtime.ml` and rebuild. Do not paper over it with a re-export from `eval_builtins`.

- [ ] **Step 1: Extract `eval_runtime.ml` (the SHARED cluster), as its own commit**

Move every SHARED name from Step 0 — definitions plus the state cells they close over (the actor registry hashtable, the pid counters, the timer queue, the type tables). These are scattered across the `Actor runtime` (:144), `Dynamic Supervisor state` (:247), `Phase 1: Monitors, Links, and crash_actor` (:1796), and FFI-table sections; move by name, not by range, and keep each moved definition's doc comment.

The cluster must itself satisfy the invariant: it may reference only `Eval_types`, `Eval_prim`, and the Phase-1 siblings. `spawn_child_actor` re-enters evaluation via `!eval_expr_hook` (:2249) — that is already a hook call, so it moves cleanly. If any moved helper calls `eval_expr`/`apply` *directly*, route it through the `Eval_prim` hook first.

Then add re-exports in `eval.ml` for every moved name that is used **outside** `lib/eval`. Generate the list rather than guessing:

```bash
grep -rhoE '\bEval\.[a-z_][a-zA-Z0-9_]*' --include='*.ml' . | sort -u | sed 's/Eval\.//' > /tmp/eval-external-510e49.txt
comm -12 /tmp/eval-external-510e49.txt <(grep -oE '^let ([a-z_][a-z0-9_]*)' lib/eval/eval_runtime.ml | sed 's/^let //' | sort -u)
```

Each name printed gets `let <name> = Eval_runtime.<name>` in `eval.ml` (known at review: `actor_registry` 56 sites, `monitor_actor` 16, `ring_get` 12 — the exact set depends on what Step 0 classified).

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "ir_exit=$?"
scripts/run-tests.sh eval; echo "suite_exit=$?"
git add lib/eval/eval_runtime.ml lib/eval/eval.ml && git commit -m "refactor(eval): extract shared runtime state to eval_runtime.ml"
```

- [ ] **Step 2: Confirm the table's one-way dependency on the evaluator still holds**

```bash
S=$(grep -n '^let base_env : env' lib/eval/eval.ml | cut -d: -f1)
E=$(grep -n '(\* Evaluation' lib/eval/eval.ml | cut -d: -f1)
awk -v s=$S -v e=$E 'NR>=s && NR<e' lib/eval/eval.ml | grep -cE '\beval_(expr|decl|module)\b'
```

Expected: **0**. This is the load-bearing premise of the table move. If non-zero, the offending references must go through `!Eval_prim.eval_expr_hook` / `!Eval_prim.apply_hook` before proceeding.

- [ ] **Step 3: Move the table AND its exclusive helpers into `eval_builtins.ml`**

```bash
{ echo '(** [base_env] — the delta-rule builtin table (core-march.md §4.4).'
  echo
  echo '    590 entries, plus the helpers only this table uses.  Extracted'
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

- [ ] **Step 4: Write the interface file — export ONLY the table**

```ocaml
(** The delta-rule builtin environment.  See eval_builtins.ml.

    [base_env] is the sole export: the helpers behind it are implementation
    detail, and hiding them here is what keeps "is this helper already
    defined somewhere?" answerable. *)

val base_env : Eval_types.env
```

`Eval_types.env` is `(string * value) list`, created in Task 1.0. This signature is exact.

- [ ] **Step 5: Add the re-export to `eval.ml`**

At the position the table used to occupy:

```ocaml
(* [base_env] moved to eval_builtins.ml (5,187 lines, 590 entries).  Re-exported
   here because [Eval.base_env] has 27 external call sites across the compiler
   and test suite. *)
let base_env = Eval_builtins.base_env
```

- [ ] **Step 6: Build, verify IR, run the FULL suite**

This is the largest single move in the plan; the eval suite alone is not enough.

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "ir_exit=$?"
scripts/run-tests.sh > /tmp/suite-t13-510e49.log 2>&1; echo "suite_exit=$?"; diff <(grep -oE '[0-9]+ (passed|failed)' /tmp/suite-base-510e49.log) <(grep -oE '[0-9]+ (passed|failed)' /tmp/suite-t13-510e49.log)
```

Expected: `ir_exit=0`, `suite_exit=0`, and an empty diff of the pass/fail counts.

- [ ] **Step 7: Commit**

```bash
git add lib/eval/eval_builtins.ml lib/eval/eval_builtins.mli lib/eval/eval.ml && git commit -m "refactor(eval): extract 590-entry base_env builtin table to eval_builtins.ml"
```

### Task 1.4: Add § navigation headers to what remains

**Files:** Modify `lib/eval/eval.ml`

- [ ] **Step 1: Number the existing section headers**

`eval.ml` already has 70 header comments but they are unnumbered rules (`(* ---- *)`), so they cannot be jumped to by name. Convert the ~34 titled ones to the numbered form `typecheck.ml` uses:

```ocaml
(* =================================================================
   §7  Pattern matching
   ================================================================= *)
```

Keep the existing titles verbatim (`Value type`, `Actor runtime`, `Dynamic Supervisor state`, `Tap bus`, `Ring buffer helpers`, `Debug trace types`, `Exceptions`, `March call stack for backtraces`, `Pattern matching`, `Built-in environment`, `FFI extern stub table`, `Dynamic FFI`, `FFI Marshal Layer`, `Show dispatch helper`, `Evaluation`, `Task builtins`, `App / Supervisor machinery`, `Module evaluation`, `Test runner`, `Doctest runner`). Number them in file order.

- [ ] **Step 2: Add a table of contents at the top of the file**

Immediately below the module docstring, list every § with its title. This is what makes the file greppable by concept rather than by symbol.

- [ ] **Step 3: Verify comments-only, then commit**

```bash
dune build bin/main.exe 2>&1 | tail -3 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "exit=$?"
git add lib/eval/eval.ml && git commit -m "docs(eval): number section headers and add a table of contents"
```

---

## Phase 2 — `llvm_emit.ml`: the 3,985-line function

`emit_expr` is 76% of its file (4,298 of 5,659 lines at `e9adc190` — it grew ~450 lines in the 30 commits after this plan was drafted): a flat **100+-arm match** in which 58 arms dispatch on a raw string (`when f.Tir.v_name = "task_await"`) and 7 more on `is_*` predicates. Two properties make it the highest-risk file in the compiler:

1. **Arm order is semantically load-bearing.** The specialized `ELet (tmp_v, EApp …)` arms at :1282 and :1440 shadow the generic `ELet` at :1541. An arm inserted in the wrong place silently never fires — no type error, no test failure unless a test covers that exact builtin.
2. **String-keyed dispatch is invisible to the compiler.** Nothing checks the 50-name set for exhaustiveness, overlap, or typos. This is the mechanism behind this repo's recurring builtin-multi-site bug class.

**Important:** this conversion is behavior-preserving, so **the IR oracle applies to Phase 2 exactly as it does to Phase 1**. A correct variant conversion emits byte-identical IR. Do not accept "the IR changed but I think it's fine" — if IR changes, the conversion is wrong.

### Task 2.1: Introduce `Builtin_name.t`

**Files:**
- Create: `lib/tir/builtin_name.ml`, `lib/tir/builtin_name.mli`
- Modify: `lib/tir/dune` — **explicit `(modules …)` list; the new module is silently not compiled until added**

**Interfaces:**
- Produces: `type t` with one constructor per emitted builtin (58 at `e9adc190`); `val of_string : string -> t option`; `val to_string : t -> string`; `val all : t list`.

- [ ] **Step 1: Regenerate the authoritative name list from the source**

Do not copy the list from this plan — derive it, so the task cannot drift from the code:

```bash
awk 'NR>1222 && NR<5210' lib/tir/llvm_emit.ml | grep -oE 'v_name = "[a-z0-9_.]+"' | sed 's/v_name = //' | tr -d '"' | sort -u
```

Expected: **58** names at `e9adc190` (the worktree was fast-forwarded to this on 2026-08-23; it was 50 at `1f5a0111` — eight `vault_*`/`root_cap` arms landed in between, which is exactly the drift this variant exists to catch). At `1f5a0111` the 50 were: `actor_register actor_reply bool_to_string chan_choose chan_send float_to_string get_work_pool html_auto_escape html_escape_ctx int_abs int_div int_div_euclid int_max_value int_min_value int_mod int_mod_euclid int_not int_popcount int_pow int_to_string mpst_send negate not pmap_threshold receive record_from_list record_get record_has_key record_put remote_ref_hashes send signal_raise_self signal_unwatch signal_watch task_await task_await_unwrap task_cancel task_cancel_by_id task_cancel_token_new task_is_cancelled task_reductions task_spawn task_spawn_steal task_spawn_with_cancel task_yield to_string vault_push_capped vault_put_new vault_set vault_set_ttl`. The eight added since: `root_cap vault_drop vault_get vault_incr vault_ns_drop vault_ns_get vault_ns_set vault_update`. If the count differs from what this plan says, **the command wins** — use what it prints, add the constructors, and note the drift in the commit message.

- [ ] **Step 2: Write `builtin_name.ml`**

```ocaml
(** Codegen-dispatched builtin names, as a variant rather than raw strings.

    [emit_expr] previously dispatched 50 builtins with
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

- [ ] **Step 3: Write `builtin_name.mli`**

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

- [ ] **Step 4: Add the module to `lib/tir/dune` — REQUIRED**

The `(modules …)` list is explicit. Insert `builtin_name` at the front, next to `tir_names`:

```
 (modules builtin_name tir_names rc_types tir pp trmc lower_types lower_state ...)
```

- [ ] **Step 5: Write the round-trip test**

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
  Alcotest.(check int) "constructor count" 58
    (List.length March_tir.Builtin_name.all)
```

Register it in the same list the other `test_codegen` cases use.

- [ ] **Step 6: Build and run**

```bash
dune build test/run_codegen.exe 2>&1 | tail -5 && ./_build/default/test/run_codegen.exe -e 2>&1 | tail -5; echo "exit=$?"
```

Expected: exit 0, the new test passing. `builtin_name.ml` is not yet referenced by the emitter, so IR must still be identical:

```bash
dune build bin/main.exe && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "exit=$?"
```

- [ ] **Step 7: Commit**

```bash
git add lib/tir/builtin_name.ml lib/tir/builtin_name.mli lib/tir/dune test/test_codegen.ml && git commit -m "feat(tir): add Builtin_name variant for codegen-dispatched builtins"
```

### Task 2.2: Convert `emit_expr`'s string guards to the variant

**Files:** Modify `lib/tir/llvm_emit.ml`

**Interfaces:**
- Consumes: `March_tir.Builtin_name.of_string` from Task 2.1.

- [ ] **Step 1: Understand what must NOT move**

```bash
awk 'NR>1222 && NR<1610 && /^  \| /{print NR": "substr($0,1,60)}' lib/tir/llvm_emit.ml
```

The structural arms — `EAtom`, the four specialized `ELet (tmp_v, EApp …)` / `ESeq (EApp …, dec_chain)` arms at :1233/:1282/:1359/:1440/:1493, the generic `ELet` at :1541, and `ESeq` at :1579 — **must keep their exact current relative order**. They pattern-match on TIR *shape*, not on builtin name, and the specialized ones deliberately shadow the generic ones. Only the `EApp (f, args) when f.Tir.v_name = "…"` arms are in scope for this task.

- [ ] **Step 2: Convert one arm first and prove the technique**

Start with `int_popcount` (:2121) — single argument, no control flow, easy to eyeball. Change:

```ocaml
  | Tir.EApp (f, [a]) when f.Tir.v_name = "int_popcount" ->
```

to a match on the decoded variant. Introduce a single guarded dispatch arm placed **where the first in-variant name arm currently sits** — that is `not` at :1853. The symbolic-operator string guards above it (`"&&"` :1839, `"||"` :1846) are NOT in the variant and keep their own arms, and the predicate arms (`is_int_arith` :1607, `is_int_cmp` :1644, `is_float_arith` :1824) stay exactly where they are. That placement keeps ordering relative to the structural and predicate arms unchanged:

```ocaml
  | Tir.EApp (f, args) when Builtin_name.of_string f.Tir.v_name <> None ->
      emit_builtin ctx (Option.get (Builtin_name.of_string f.Tir.v_name)) f args
```

and define `emit_builtin` as a new mutually-recursive function (`and emit_builtin ctx b f args = match b with …`) carrying the converted arms.

**Fall-through semantics change here — handle it explicitly.** Today `| Tir.EApp (f, [a]) when f.Tir.v_name = "task_await"` matches only the 1-arg shape; any other shape falls through to the later generic-application arms. The consolidated arm captures *every* arity for all 50 names, so `emit_builtin` must provide that escape itself. Factor the body of the current generic `EApp` arm into a callable `and emit_generic_app ctx f args = …`, and inside `emit_builtin` give every constructor's shape-match a final `| _ -> emit_generic_app ctx f args` arm:

```ocaml
and emit_builtin ctx (b : Builtin_name.t) f args =
  match b with
  | Builtin_name.Task_await ->
      (match args with
       | [a] -> (* body of the :2201 arm, verbatim *)
       | [a; b] -> (* body of the :2269 arm, verbatim *)
       | _ -> emit_generic_app ctx f args)
  | Builtin_name.Int_popcount ->
      (match args with
       | [a] -> (* body of the :2121 arm, verbatim *)
       | _ -> emit_generic_app ctx f args)
  (* … one outer arm per constructor, no outer wildcard … *)
```

The outer match on `b` is the exhaustiveness surface (Step 5); the inner matches on `args` keep the generic escape. That is fall-through preservation, not a hole.

- [ ] **Step 3: Verify after the FIRST arm, before converting the other 49**

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "exit=$?"
```

Expected: `IR IDENTICAL`, `exit=0`. **If IR changed here, stop and diagnose** — the technique is wrong and converting 49 more arms will bury the cause.

- [ ] **Step 4: Convert the remaining 49 arms in batches of ~10**

After each batch: rebuild, run the oracle, and only then continue. A batch that changes IR is reverted and redone one arm at a time.

Two arms need care because their guards are not simple equality:
- `task_await` appears **twice** (:2201 and :2269) with different argument shapes. Preserve both, distinguished inside `emit_builtin` by matching on `args`, in the same order.
- `html_auto_escape` appears twice (:1896, :1921), likewise.

- [ ] **Step 5: Make the match exhaustive**

Once all 50 are converted, `emit_builtin`'s **outer match on the constructor** must have no `| _ ->` arm, so that adding a constructor to `Builtin_name.t` becomes a compile error (warning 8 is an error under the dev profile — verified). The inner per-constructor matches on `args` DO keep their `emit_generic_app` escape — that is the fall-through preservation from Step 2, not a catch-all over constructors. Confirm:

```bash
grep -n 'and emit_builtin' lib/tir/llvm_emit.ml
```

Then read the function's final arm and verify it is a named constructor, not a wildcard.

- [ ] **Step 6: Prove the exhaustiveness check actually fires**

```bash
sed -i.bak 's/^  | Vault_set_ttl$/  | Vault_set_ttl\n  | Probe_unused/' lib/tir/builtin_name.ml && dune build bin/main.exe 2>&1 | grep -c 'not exhaustive\|Error'
```

Expected: a non-zero count — the build **fails**. That is the whole point of the task. Revert:

```bash
git checkout lib/tir/builtin_name.ml && rm -f lib/tir/builtin_name.ml.bak && dune build bin/main.exe 2>&1 | tail -3
```

- [ ] **Step 7: Full verification**

```bash
scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "ir_exit=$?"
scripts/run-tests.sh > /tmp/suite-t22-510e49.log 2>&1; echo "suite_exit=$?"
./_build/default/test/run_snapshots.exe -e > /tmp/snap-t22-510e49.log 2>&1; echo "snap_exit=$?"
```

Expected: all three exit 0. IR identical is the strong claim here — the refactor changed dispatch mechanism, not emitted code.

- [ ] **Step 8: Commit and record the user-visible change**

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

- [ ] **Step 1: Add all three modules to `lib/tir/dune`'s `(modules …)` list**

Do this **first**, in the same commit — a module missing from the list is silently not compiled, and the resulting error is confusing.

- [ ] **Step 2: Move `emit_builtin`'s arms by topic**

- `llvm_emit_arith.ml`: `Int_abs`, `Int_div`, `Int_div_euclid`, `Int_max_value`, `Int_min_value`, `Int_mod`, `Int_mod_euclid`, `Int_not`, `Int_popcount`, `Int_pow`, `Int_to_string`, `Bool_to_string`, `Float_to_string`, `Negate`, `Not`, `To_string`
- `llvm_emit_task.ml`: all `Task_*`, `Actor_*`, `Signal_*`, `Send`, `Receive`, `Chan_*`, `Mpst_send`, `Get_work_pool`, `Pmap_threshold`, `Remote_ref_hashes`
- `llvm_emit_record.ml`: all `Record_*`, all `Vault_*`, both `Html_*`

Each module exports one function taking the emitter context, e.g. `val emit : Llvm_ctx.t -> Builtin_name.t -> Tir.value -> Tir.atom list -> (string * string) option`, returning `None` for a constructor it does not own. `emit_builtin` in `llvm_emit.ml` becomes a three-way chain that **must still end in an exhaustive match** — keep a final `match b with` listing every constructor and routing it, so exhaustiveness is preserved across the split.

- [ ] **Step 3: Verify and commit**

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "ir_exit=$?"
scripts/run-tests.sh codegen; echo "suite_exit=$?"
git add lib/tir/llvm_emit_arith.ml lib/tir/llvm_emit_task.ml lib/tir/llvm_emit_record.ml lib/tir/llvm_emit.ml lib/tir/dune && git commit -m "refactor(tir): split emit_builtin arms into arith/task/record modules"
```

---

## Phase 3 — `refine_check.ml`: navigation and the 12-parameter flood

7,416 lines with **zero section headers** — the only file in this set with no navigational structure at all. `check_call` is 1,361 lines behind a twelve-parameter signature. It has **three** call sites, all inside the `visit` traversal (`refine_check.ml:5695`, `:5719`, `:5731`), so the parameter bundle can be changed with a bounded blast radius — but all three must be read, not one.

**The IR oracle does not apply here** — refinement checking affects diagnostics, not emitted code. Phase 3 needs its own oracle, and building it requires clearing two caches that otherwise produce vacuous green:

- `--refine-report` prints nothing on a warm CAS. Clear `.march/cas/artifacts-v2/` (**not** `artifacts/`, which is an inert v1 pointer store).
- The refinement VC cache masks regression tests. Clear `.march/cas/vc` **once before** a verdict run, never during one.

### Task 3.1: Build the refinement diagnostic oracle

**Files:** Create `scripts/refine-oracle.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Refinement-diagnostic oracle.  refine_check affects DIAGNOSTICS, not emitted
# code, so the IR oracle cannot see its regressions.
#
# Both caches below produce vacuous green if left warm:
#   .march/cas/artifacts-v2  -> --refine-report prints NOTHING on a hit
#   .march/cas/vc            -> verification conditions are reused, masking
#                               a checker that stopped checking
# Cleared ONCE here, before the run — never between fixtures.
set -uo pipefail
MODE="${1:?usage: refine-oracle.sh {baseline|check} <dir>}"
DIR="${2:?usage: refine-oracle.sh {baseline|check} <dir>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="$ROOT/_build/default/bin/main.exe"
OUT="$DIR/refine.txt"

[ -x "$EXE" ] || { echo "FATAL: $EXE not built"; exit 2; }
rm -rf "$ROOT/.march/cas/artifacts-v2" "$ROOT/.march/cas/vc"
mkdir -p "$DIR"; : > "$DIR/run.tmp"

n=0
for f in "$ROOT"/test/native/*.march "$ROOT"/stdlib/*.march; do
  [ -e "$f" ] || continue
  tag="$(basename "$(dirname "$f")")_$(basename "$f" .march)"
  # Normalise absolute paths so the manifest is machine-independent.
  "$EXE" --check --refine-report "$f" 2>&1 | sed "s|$ROOT/||g" \
    | sed "s|^|$tag: |" >> "$DIR/run.tmp"
  n=$((n+1))
done
sort "$DIR/run.tmp" > "$DIR/run.sorted"
lines=$(wc -l < "$DIR/run.sorted")
echo "fixtures=$n report_lines=$lines"

if [ "$lines" -lt 50 ]; then
  echo "FATAL: only $lines report lines — the refinement checker is not running"
  echo "(warm cache? --refine-report short-circuited?).  Refusing to record."
  exit 2
fi

case "$MODE" in
  baseline) cp "$DIR/run.sorted" "$OUT"; echo "baseline recorded: $OUT" ;;
  check)
    [ -f "$OUT" ] || { echo "FATAL: no baseline at $OUT"; exit 2; }
    if diff -u "$OUT" "$DIR/run.sorted" > "$DIR/refine.diff"; then
      echo "REFINEMENT DIAGNOSTICS IDENTICAL ($lines lines)"; exit 0
    else
      echo "DIAGNOSTICS CHANGED:"; head -40 "$DIR/refine.diff"; exit 1
    fi ;;
  *) echo "unknown mode: $MODE"; exit 2 ;;
esac
```

- [ ] **Step 2: Record the baseline and prove it is non-vacuous**

```bash
chmod +x scripts/refine-oracle.sh && scripts/refine-oracle.sh baseline /tmp/refine-base-510e49; echo "exit=$?"
```

Expected: `report_lines=` a number **≥ 50**, exit 0. A `FATAL: only N report lines` means the cache clear did not take — investigate before proceeding.

Runtime note: ~280 fixtures, each a z3-backed check — expect **minutes, not seconds**. Let it finish. A half-run baseline is worse than none: the guard catches `< 50` lines, but it cannot tell a truncated-yet-large baseline from a complete one.

- [ ] **Step 3: Commit**

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
dune build bin/main.exe 2>&1 | tail -3 && scripts/refine-oracle.sh check /tmp/refine-base-510e49; echo "exit=$?"
git add lib/refinecheck/refine_check.ml && git commit -m "docs(refinecheck): add numbered section headers and a table of contents"
```

### Task 3.3: Bundle `check_call`'s parameters into a record

**Files:** Modify `lib/refinecheck/refine_check.ml`

**Interfaces:**
- Produces: `type call_ctx = { root : …; errctx : …; lets : launder; postcond : string -> A.expr list -> (string * A.expr * string option) option; rp : rparam; sc : scope; re : recenv }` — the seven parameters that are *constant across the whole traversal*. The four that vary per call (`~span`, `~callee`, `sg`, `args`, `path`) stay as explicit parameters.

- [ ] **Step 1: Read the current signature and classify each parameter**

```bash
sed -n '3371,3376p' lib/refinecheck/refine_check.ml
```

Current: `~root errctx ~span ~(callee : string) ?(subject = Argument) ?(verdict_out) ~(lets : launder) ~(postcond) (sg : fn_sig) (args) (path) (rp : rparam) (sc : scope) (re : recenv)`.

Classify by tracing **all three call sites** — `refine_check.ml:5695`, `:5719`, `:5731`, all inside the `visit` traversal: a parameter passed unchanged at every site on every iteration is *context*; one that varies at **any** site is a *parameter*. Do not guess, and do not stop after the first site — an argument constant at one can vary at another.

- [ ] **Step 2: Define the record next to `check_call`, with a docstring per field**

Each field's comment says what it is and why it is threaded — this is the documentation that does not exist today and is the main reason the function is hard to edit.

- [ ] **Step 3: Change the signature and all three call sites**

Build the record once, where `visit` binds the traversal-constant values, and pass it at `:5695`, `:5719`, and `:5731`.

- [ ] **Step 4: Verify diagnostics are unchanged**

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/refine-oracle.sh check /tmp/refine-base-510e49; echo "refine_exit=$?"
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
dune build bin/main.exe 2>&1 | tail -5 && scripts/refine-oracle.sh check /tmp/refine-base-510e49 && scripts/run-tests.sh compiler; echo "exit=$?"
git add lib/refinecheck/refine_check.mli && git commit -m "refactor(refinecheck): add refine_check.mli documenting the public API"
```

---

## Phase 4 — `analysis.ml`: split the code-action engines

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
dune build lsp/ 2>&1 | tail -5 && dune build lsp/test/test_lsp.exe && ./_build/default/lsp/test/test_lsp.exe -e 2>&1 | tail -5; echo "exit=$?"
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

`compile` is 2,360 lines, but linear driver code is the *friendliest* shape to work in — no hidden coupling, read the window you need. This phase does **not** split it. It fixes one thing: `cas_flags` is constructed at **two** sites (`main.ml:2325` and `main.ml:3606`), and a codegen flag added to one and not the other silently produces cache hits across semantically different builds.

### Task 5.1: Extract `cas_flags` construction

**Files:** Modify `bin/main.ml`

- [ ] **Step 1: Diff the two sites**

```bash
diff <(sed -n '2325,2343p' bin/main.ml) <(sed -n '3606,3624p' bin/main.ml)
```

Record every difference. Some are legitimate (the second site adds sysroot `.so` digests per the comment at :3595); those become parameters, not divergence.

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

Move the existing `MARCH_DEBUG_CASFLAGS` debug print (`main.ml:3625-3627`) **into** this function so that every call site logs its flag list identically — that print is what Step 3 verifies against.

- [ ] **Step 3: Prove the flag LIST is unchanged — never compare cache keys across compiler builds**

The CAS key includes the digest of the compiler executable itself. Any comparison that spans "rebuild the compiler" therefore **always** yields different keys — an artifact-count check is structurally incapable of validating this refactor, and a naive reading of its inevitable failure invites a wrong "fix". Compare the flag *list* instead.

Site 2 (`main.ml:3625`) already has an env-gated print; site 1 (`:2343`) has none. So first, as a print-only preparatory change, copy the same three-line `eprintf` to site 1, directly after its `let ch = … compilation_hash …` line. A print cannot alter the key. Build and capture the "before" flag lists with a flag that must be key-distinct (`--cap-strict`) in one run and not the other:

```bash
dune build bin/main.exe 2>&1 | tail -3
echo 'fn main() do println("cas-probe") end' > /tmp/cas-probe-510e49.march
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile -o /tmp/cas-probe-510e49.bin /tmp/cas-probe-510e49.march > /tmp/casflags-before-a-510e49.log 2>&1
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile --cap-strict -o /tmp/cas-probe-510e49.bin /tmp/cas-probe-510e49.march > /tmp/casflags-before-b-510e49.log 2>&1
grep -c MARCH_CASFLAGS /tmp/casflags-before-a-510e49.log /tmp/casflags-before-b-510e49.log
```

Expected: **non-zero** counts for both. A zero means the probe did not reach a printing site — the capture is vacuous; do not proceed until it prints.

Now apply the Step-2 refactor (the print moves into `build_cas_flags`), rebuild, recapture, and diff the flag lists only:

```bash
dune build bin/main.exe 2>&1 | tail -3
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile -o /tmp/cas-probe-510e49.bin /tmp/cas-probe-510e49.march > /tmp/casflags-after-a-510e49.log 2>&1
MARCH_DEBUG_CASFLAGS=1 ./_build/default/bin/main.exe --compile --cap-strict -o /tmp/cas-probe-510e49.bin /tmp/cas-probe-510e49.march > /tmp/casflags-after-b-510e49.log 2>&1
diff <(grep -o 'flags=\[[^]]*\]' /tmp/casflags-before-a-510e49.log) <(grep -o 'flags=\[[^]]*\]' /tmp/casflags-after-a-510e49.log); echo "a_exit=$?"
diff <(grep -o 'flags=\[[^]]*\]' /tmp/casflags-before-b-510e49.log) <(grep -o 'flags=\[[^]]*\]' /tmp/casflags-after-b-510e49.log); echo "b_exit=$?"
```

Expected: `a_exit=0` and `b_exit=0` — the flag lists are byte-identical, so the key is unchanged for any fixed compiler binary. The `ch=` hashes in the before/after logs **will** differ because the compiler was rebuilt between captures; that is the compiler-digest component doing its job, not a regression. Also confirm the `b` list contains `capstrict` and the `a` list does not — otherwise the probe is not exercising flag-sensitivity.

- [ ] **Step 4: Verify and commit**

```bash
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49 && scripts/run-tests.sh codegen; echo "exit=$?"
git add bin/main.ml && git commit -m "refactor(main): construct CAS cache-key flags in exactly one place"
```

---

## Phase 6 — `typecheck.ml`: cold data only (DOWNSCOPED)

Done last, deliberately. This is the **best-decomposed** file in the set (223 top-level definitions, 21 § sections, largest function only 10% of the file) and the **most contended** (34 of the last 300 commits). Every line moved here is a rebase risk for concurrent work.

**Downscoped at review (2026-08-23).** The first draft extracted `builtin_bindings` and `pp_ty`. Both are coupled to the `ty`/`scheme` types defined *inside* `typecheck.ml` — measured: the `builtin_bindings` range uses `TArrow` ×956, `TCon` ×539, `Mono` ×451, plus `Poly`/`TTuple`/`TVar`; `pp_ty` pretty-prints `ty` and reads the `_tvar_names`/`_record_names` tables. Extracting either therefore requires *first* extracting the core type definitions to a `typecheck_types.ml` — a structural change to the hottest file in the repo, for a navigation win its 21 § headers already mostly deliver. The earlier "zero coupling" claim checked only for calls into the inference core and missed the type constructors; it was wrong. Not worth the rebase risk now. If a `typecheck_types.ml` ever exists for other reasons, revisit both extractions. Verification recipe for that day: the IR oracle, the full suite, **and** `dune build @types-check --force` judged by its log contents — `pp_ty` feeds diagnostic text, that CI-only alias asserts exact message strings, and without `--force` it exits 0 with a zero-byte log (vacuous).

What remains in scope is the one genuinely uncoupled item.

`lib/typecheck/dune` has no `(modules …)` field — new files are picked up automatically.

### Task 6.1: Extract `builtin_cap_table`

`builtin_cap_table` is a 140-line pure `(string * string) list` literal — no `ty`, no `scheme`, no helper calls.

**Files:**
- Create: `lib/typecheck/builtin_caps.ml`
- Modify: `lib/typecheck/typecheck.ml`

**Interfaces:**
- Produces: `Builtin_caps.table : (string * string) list`. `typecheck.ml` keeps `let builtin_cap_table = Builtin_caps.table` at the original position so no other line in the file changes.

- [ ] **Step 1: Confirm zero type coupling before moving**

```bash
S=$(grep -n '^let builtin_cap_table' lib/typecheck/typecheck.ml | cut -d: -f1)
sed -n "${S},$((S+140))p" lib/typecheck/typecheck.ml | grep -cE '\b(Mono|Poly|TArrow|TCon|TVar|TTuple|scheme)\b'
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
dune build bin/main.exe 2>&1 | tail -5 && scripts/ir-oracle.sh check /tmp/ir-base-510e49; echo "ir_exit=$?"
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
scripts/check-docs.sh > /tmp/doclint-510e49.log 2>&1; echo "exit=$?"; tail -20 /tmp/doclint-510e49.log
```

Note: doc-lint has been green locally and red in CI before, because CI tests the **merge ref**, not your tip. Before opening a PR: `git fetch origin && git merge origin/main` (never bare `git merge main` — it merges a stale local ref), then re-run.

- [ ] **Step 4: Final full-suite verification**

```bash
scripts/run-tests.sh > /tmp/suite-final-510e49.log 2>&1; echo "exit=$?"
diff <(grep -oE '[0-9]+ (passed|failed)' /tmp/suite-base-510e49.log) <(grep -oE '[0-9]+ (passed|failed)' /tmp/suite-final-510e49.log)
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
- **Line numbers drift.** Every task after the first move in its file re-locates its boundary by `grep` rather than trusting a number from this document. Line numbers here are from `1f5a0111`.

## Review revisions (2026-08-23)

A verification pass against the codebase — checking the plan's load-bearing claims rather than its prose — found five defects in the first draft. All are fixed inline above; they are recorded here so an executing agent understands *why* the structure looks the way it does, and does not "simplify" it back into a bug.

1. **Module cycle in Phase 1 (critical — would not compile).** Every extraction block referenced `eval_error` (base_env ×717, session ×10, net ×4, simd ×1) and the hook refs (base_env ×41, net ×4), all of which the first draft left in `eval.ml`. Since `eval.ml` depends on the extracted modules, that is a cycle. The draft's "leaf check" also tested the wrong direction (references *below* the block, when the real rule is references to *anything remaining in `eval.ml`*). Fixes: new Task 1.0b (`eval_prim.ml`); Task 1.3 rewritten as a shared/exclusive split with `eval_runtime.ml` (27 shared helpers measured, 85 exclusive); dependency-check criteria corrected in Tasks 1.1–1.2.
2. **Phase 6 downscoped (critical — would not compile).** `builtin_bindings` uses `TArrow` ×956 / `TCon` ×539 / `Mono` ×451; `pp_ty` prints `ty`. Both need the type definitions extracted first, in the most contended file. The draft's "zero coupling" verification only looked for calls into the inference core. Dropped; only the genuinely uncoupled `builtin_cap_table` remains.
3. **`check_call` has three call sites** (`:5695`, `:5719`, `:5731`), not one — the draft's grep was `head`-truncated. Task 3.3's classification and threading corrected.
4. **`code_actions_at` signature.** The draft's composition dropped `?(diagnostics = [])` and the trailing `()`, which would break every `test_lsp.ml` call site and the server. Now preserved verbatim.
5. **Phase 5 verification method was structurally unable to pass.** The CAS key includes the compiler's own digest, so comparing keys across two compiler builds always differs. Replaced the artifact-count comparison with a `MARCH_DEBUG_CASFLAGS` flag-list diff; that env-gated print already existed at `main.ml:3625` and now lives inside `build_cas_flags` so both sites log.

Also hardened **Task 2.2**: the consolidated dispatch arm changes fall-through semantics (shape-mismatched calls previously fell through to the generic-app arms), so `emit_builtin` factors the generic arm into `emit_generic_app` and keeps it as each constructor's inner-match escape while the outer constructor match stays exhaustive. Placement wording corrected: the first *in-variant* arm is `not` at `:1853`; the `"&&"`/`"||"` string guards above it are not in the variant. And **Task 3.1** now states the refine oracle's multi-minute runtime so a baseline is not killed mid-run.

Verified and unchanged by the review: the IR oracle design and its determinism; warning 8 as a build error; the Task 1.0 type-block boundary (17–142, no interleaved `let`); the `analysis.ml` non-duplication finding; the 50-name builtin list.
