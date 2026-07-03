# Wave 2: println-of-list Miscompile Fix + Testing Infrastructure

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the newly-diagnosed interface-dispatch miscompile (compiled `println([1,2,3])` has never worked), then land the three highest-leverage testing-infrastructure items from `specs/analysis/2026-07-01-pipeline-deep-review.md` §8: loud skips, an IR validity gate, and TIR snapshot tests.

**Architecture:** Task 1 is a compiler fix (mono.ml substitution propagation + llvm_emit fallback hardening) specified by a completed root-cause diagnosis. Tasks 2–4 are test-harness work only (test/, plus dune wiring). Task 5 is bookkeeping.

**Tech Stack:** OCaml 5.3 / dune / alcotest; LLVM toolchain for the IR gate.

## Global Constraints

- **Worktree:** work ONLY in `/Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3` on branch `claude/hopeful-kapitsa-9f49f3` (currently == main; the controller handles the end-of-wave merge).
- **Off-limits files:** `lib/tir/perceus.ml`, `lib/tir/borrow.ml`, `test/test_properties.ml`. A concurrent session ("dynamic-record RC/GC crash") may be active around `runtime/march_extras.c` and llvm_emit's EUpdate region — do not edit those regions unless your task explicitly requires it.
- **Build/test recipe (scripts/run-tests.sh does NOT work from this worktree):** `dune build --root .`; five runners via `dune build --root . test/run_compiler.exe test/run_eval.exe test/run_codegen.exe test/run_stdlib.exe test/test_stdlib_march.exe` then each `./_build/default/test/<t>.exe -e`; judge by EXIT CODE. Full five-runner suite exit 0 before every commit.
- **Foreground only** — never background a long command and wait. No `git stash` (shared stash stack; use file copies or `git checkout <sha> -- <file>`). macOS: no `timeout` command.
- **Benchmarks** (codegen-affecting tasks only, marked): compiled form ONLY — `./_build/default/bin/main.exe --compile --opt 2 bench/<n>.march -o /tmp/wave2-kapitsa-<n>` then run; compare to `specs/benchmarks.md`. Never interpret bench files.
- **TDD:** failing test first (RED proving the bug/gap), then implement (GREEN). Record both in the report.
- **Commits:** one per task, explicit staging by name, no Co-Authored-By, message format given per task.
- **deciduous:** before first edit `deciduous add action "<task title>" -c 85` + `deciduous link 1545 <id> -r "Wave 2 task"`; after commit an outcome node `--commit HEAD` linked from your action.
- **Hang triage:** stale dune daemon (`dune shutdown`); shared `~/.cache/march` JIT cache poisoning (isolate with `HOME=<scratch>`); leftover `main.exe` processes.
- **Known pre-existing failures (NOT yours):** `bench/heapsort.march` RC underflow; `examples/supervision_linear_drop.march` race; the record-mutation-loop SIGSEGV (separate session).
- **March syntax:** `mod Name do ... end`; `if c do ... else ... end` (else required); lambdas `fn x -> body`; nothing named `init`.

---

### Task 1: Fix interface-impl monomorphization — compiled `println([1,2,3])` miscompiles (empty substitution + suffix-map hijack)

**Files:**
- Modify: `lib/tir/mono.ml` (impl-enqueue sites ~:416, :440, :549 — re-locate by reading; they enqueue resolved interface impls with an empty substitution)
- Modify: `lib/tir/llvm_emit.ml` (`unqualified_fns` dot-suffix fallback, ~:6658–6673 and its consumer ~:3740–3746 — re-locate by grepping `unqualified_fns`)
- Test: `test/test_codegen.ml`

**Interfaces:** specialized impl symbol naming — if you introduce e.g. `Show$List.show$Int`, document the mangle at the mono site AND anywhere llvm_emit/defun must recognize it. Check `Tir_names`-style helpers don't exist yet (they don't — Wave 3); keep the mangle local and commented.

**THE SPEC IS THE DIAGNOSIS REPORT — read it first:** `.superpowers/sdd/sortby-diagnosis.md`. Summary: inside `impl Show(List(a)) when Show(a)`, the element-level `show(x)` types as a TVar so lower defers resolution; mono resolves the OUTER call to `Show$List.show` but enqueues the impl with an EMPTY substitution, so the impl body stays generic and the nested `show` survives to llvm_emit unresolved; llvm_emit's `unqualified_fns` dot-suffix map then resolves bare `show` to `Show$List.show` — the list impl applied to a raw element. Symptom by element type: Int→SIGSEGV, String→non-exhaustive panic, Option→SIGBUS.

- [ ] **Step 1: RED.** Compiled-vs-interpreter parity tests (compile-and-run pattern from test_codegen.ml):

```march
mod ShowList do
  fn main() do
    println([1, 2, 3, 4, 5])
  end
end
```

plus variants: `println(["a", "b"])`, `println([Some(42), None])`, and a nested `println([[1,2],[3]])`. Assert compiled stdout == interpreter stdout AND exit 0. All must FAIL today (three different symptom classes — capture each in the report).

- [ ] **Step 2: Fix mono.** At each enqueue site for a resolved interface impl, compute the substitution from the resolved argument types (the information used to pick `Show$List` must also bind `a` := element type) and enqueue the impl specialized under it, so the nested `show(x)` resolves to the element's impl (`Show$Int.show` etc.). Follow how mono specializes ordinary generic fns — reuse that machinery rather than inventing a parallel path. Recursion guard: `List(List(Int))` must terminate (mono's existing worklist dedup should handle it — verify).
- [ ] **Step 3: Harden the fallback.** In llvm_emit's `unqualified_fns` suffix map, EXCLUDE `Iface$Type.method`-mangled names (anything matching the `$` interface-mangle shape) so an unresolved bare method can never silently bind to an arbitrary impl again — fail loudly (failwith naming the unresolved symbol and the candidates) instead. This is the wave-1 fail-loud policy applied here.
- [ ] **Step 4: GREEN.** All Step-1 tests pass; five-runner suite exit 0. [Codegen-affecting] Run the three RC benchmarks (compiled) + `bench/mutual_recursion.march`; report outputs/timings vs specs/benchmarks.md.
- [ ] **Step 5:** If the interpreter and compiled now agree on all variants, also re-run the 150-element sort_by-and-println repro from `/tmp/sortby-kapitsa-*.march` (recreate if gone) end-to-end and record the result — this formally closes the historic "sort_by crash" saga.
- [ ] **Step 6: Commit** `fix(mono,llvm): specialize interface impls with arg substitution; forbid Iface$ names in unqualified fallback (println-of-list miscompile)` — stage the two lib files + test file.

---

### Task 2: W2.0 — kill vacuous greens (loud skips)

**Files:**
- Modify: `test/test_helpers.ml` (`setup_jit_runtime`), `test/test_codegen.ml` + `test/test_stdlib_suite.ml` (compile-fail skip patterns)
- Test: new canary tests in `test/test_codegen.ml`

**Interfaces:** none; harness behavior only.

Context: three instances of tests passing by not running were found recently: (a) `setup_jit_runtime` returned `None` on .so link failure with stderr discarded → ALL clang-gated JIT tests silently no-op'd for weeks; (b) compiled tests skip when compilation fails (`if not (Sys.file_exists main_exe) then ()` pattern, 10+ occurrences); (c) the differential oracle skipped crashes (already fixed). Policy: a skip is legitimate ONLY when the environment lacks a tool; any in-repo failure (link error, compile error) is a test FAILURE.

- [ ] **Step 1: RED (demonstrate the vacuity).** Temporarily (file-copy, not stash) remove one runtime .c file from `setup_jit_runtime`'s list, run the codegen suite, and record that everything still passes (the vacuous green). Restore.
- [ ] **Step 2: Fix `setup_jit_runtime`:** distinguish "clang not installed" (legitimate skip — but COUNT and print skipped-test totals at teardown) from "clang present, link failed" → `Alcotest.fail` with the captured linker stderr. Stop discarding stderr.
- [ ] **Step 3: Fix compile-fail skips:** for each `if not (Sys.file_exists <exe>)`-style guard in test_codegen.ml/test_stdlib_suite.ml, make compilation failure fail the test with the compiler's stderr. If any test NOW fails because it was vacuously green over a real bug: fix the test if it's a test bug; if it's a product bug, convert to a LOUD documented skip (`Alcotest.skip` with reason naming a specs/todos.md entry you add) — never a silent `()`.
- [ ] **Step 4: Canary:** a test that fails if `setup_jit_runtime` returns `None` while `clang --version` succeeds — the gate-is-live assertion.
- [ ] **Step 5: Re-run Step 1's sabotage — the suite must now FAIL. Restore; five runners exit 0.**
- [ ] **Step 6: Commit** `test(harness): in-repo failures fail loudly — no silent skips for link/compile errors; JIT gate canary (W2.0)`. Report must list every vacuity exposed by Step 3 and its disposition.

---

### Task 3: W2.1 — LLVM IR validity gate

**Files:**
- Modify: `test/test_codegen.ml` (or a small new `test/test_ir_verify.ml` + dune rule — your call, justify)
- Possibly: `test/dune`

**Interfaces:** none.

Context: emitted IR is never verified; ill-typed IR (the `coerce` catch-all class) surfaces as opaque clang errors or JIT failures. Add verification of the textual IR for the native fixture corpus.

- [ ] **Step 1: Tooling probe.** Find a verifier on this machine: `opt -passes=verify -disable-output <f.ll>` or `llvm-as -o /dev/null <f.ll>` (check what the clang install provides; `xcrun -f opt` / brew LLVM). Record which is available. If NONE: implement the gate behind a tool-availability check with a loud counted skip (Task 2 policy) and say so — do not fake it.
- [ ] **Step 2: RED.** Hand-craft an invalid .ll (e.g. `add i64 %x, double 1.0`), assert your new verify helper rejects it (proves the gate detects).
- [ ] **Step 3: Gate the corpus.** For each `test/native/*.march` fixture (and any test already producing .ll via `--emit-llvm`), emit IR and run the verifier; one alcotest case per fixture or one aggregated case with per-file reporting — prefer aggregated with a failure list. Wire into run_codegen.
- [ ] **Step 4: GREEN on the real corpus** (if any fixture's IR fails verification TODAY, that's a real finding: report it, file a specs/todos.md entry, and loud-skip that fixture with the reference — do not fix emitter bugs in this task).
- [ ] **Step 5: Five runners exit 0. Commit** `test(codegen): LLVM IR validity gate over native fixture corpus (W2.1)`.

---

### Task 4: W2.2 — TIR snapshot test infrastructure

**Files:**
- Create: `test/test_snapshots.ml`, `test/snapshots/lower/*.expected`, `test/snapshots/perceus/*.expected`
- Modify: `test/dune` (new runner `run_snapshots.exe` or fold into run_compiler — prefer a separate exe so `-e` semantics stay clean; justify your choice)
- Test corpus: new small `.march` programs embedded as strings or under `test/snapshots/src/`

**Interfaces:** `UPDATE_SNAPSHOTS=1` env regenerates; document the workflow at the top of test_snapshots.ml AND in a one-paragraph addition to the march-lang/compiler docs the doc-lint guards (`scripts/check-docs.sh` must stay green).

Context: no TIR-level golden tests exist; every lowering/Perceus regression so far was caught (or missed) at runtime. Pipeline access: use the same entry points `Test_helpers.lower_module`-style tests use (test/test_helpers.ml:105–128) and whatever runs the pass pipeline up to post-Perceus (grep bin/main.ml for the pass sequence; `lib/tir/pp.ml` and tir.ml's show fns exist for printing — pick ONE canonical printer and normalize fresh-name counters if they make output nondeterministic across runs; if names are deterministic per-compile, verify by double-run diff).

- [ ] **Step 1: Corpus (12–16 programs, each < 20 lines), covering at minimum:** guarded match (post-Task-1-wave panic shape); float-literal arms; tuple/atom/string arms; a match with NO wildcard (panic default); closure capture + HOF; mixed owned/borrowed call args (the B1 shape); cross-branch consumption (value consumed in one arm, dec'd in another); borrowed-field escape; **the scrutinee-borrowed conservatism pin** (scrutinee used on one path only — snapshot documents the current leak-not-crash choice); a mutual-TCO pair; a dead-binding FBIP reuse shape; a record update.
- [ ] **Step 2: RED (infrastructure proof).** With one snapshot committed, hand-corrupt the .expected file → runner must fail with a readable diff; `UPDATE_SNAPSHOTS=1` must regenerate byte-identically; second run green.
- [ ] **Step 3: Generate all snapshots; eyeball each .expected for sanity** (the point is a HUMAN-auditable record — note in the report anything surprising you see in the IR; you are the first person to ever read these dumps systematically).
- [ ] **Step 4: Determinism check:** run the snapshot suite 3× including once with a cold `_build`-adjacent env; byte-identical.
- [ ] **Step 5: Five runners + the new runner exit 0. Commit** `test(tir): golden snapshot infrastructure — post-lower + post-perceus dumps, UPDATE_SNAPSHOTS regen (W2.2)`. Also update the compiler-rc guidance: `~/.claude/commands/compiler-rc.md` §6 previously said snapshots don't exist — correct it to describe the new workflow (outside-repo edit; note in report).

---

### Task 5: Bookkeeping

**Files:** `specs/todos.md`, `specs/progress.md`

- [ ] **Step 1:** Five runners for final counts.
- [ ] **Step 2:** todos.md: move/mark the println-of-list (historic "sort_by crash") item Done referencing the diagnosis + Task 1 commit; add entries for any vacuities/IR findings Tasks 2–3 filed. progress.md: Current State counts + Wave 2 bullet (loud-skip policy, IR gate, snapshot infra — reference this plan file).
- [ ] **Step 3:** `scripts/check-docs.sh` green. **Commit** `docs(specs): record Wave 2 (println-of-list fix + testing infrastructure)`.
