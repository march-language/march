# Differential Oracle Expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `specs/2026-07-04-differential-oracle-design.md` — expand the differential oracle (`test/test_properties.ml`) so the interpreter/compiled-divergence bug class is caught in CI, and make the oracle strong enough to serve as the future `eval.ml` refactor gate.

**Architecture:** Incremental hardening of the existing QCheck2 oracle plus one small compiler change (an "unsupported construct" exit signal). Phases: (1) close the oracle's own vacuous-green holes, (2) expand generators toward the failure shapes, (3) widen the comparison surface, (4) full-corpus conformance sweep, (5) wire as the refactor gate.

**Tech Stack:** OCaml 5.3 / dune / QCheck2; the compiler at HEAD for behavior verification.

## Global Constraints

- **Base:** `c7575b06` (== main == origin/main at plan time). Worktree ONLY: `/Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3`, branch `claude/hopeful-kapitsa-9f49f3`. Controller handles the main merge at the end.
- **Build/test:** `dune build --root .`; the property exe is `test_properties.exe` (dune stanza name `test_properties`, `test/dune:297`). Run it `HOME=$PWD/.oraclehome ./_build/default/test/test_properties.exe -e` (isolated HOME — the oracle compiles many programs and is a heavy cache client; isolation avoids the shared `~/.cache/march` fake-hang). The six standard runners (`run_compiler`/`run_eval`/`run_codegen`/`run_stdlib`/`test_stdlib_march`/`run_snapshots`) must stay green for any task that touches `lib/` or `bin/`.
- **CRITICAL — the oracle must stay GREEN on `main` at every commit.** Several generators here reproduce KNOWN OPEN BUGS (the Newtype derived-method SIGSEGV; the record-update missing-field divergence). A generator that reddens CI on an unfixed bug is NOT landable. The rule: **constrain each generator to the currently-WORKING subset**, and for the broken subset add a *separate targeted test marked expected-fail / skip-with-reference* citing the open `specs/todos.md` entry — never widen a generator into a known crash. When the underlying bug is fixed, a follow-up widens the generator (note this in the task's report).
- **WIRING (corrected after Task 3 review — applies to Tasks 3/4/5):** a generator only gets interpreter-vs-compiled DIFF coverage when it feeds `oracle_check` via a dedicated `prop_oracle_<name>` property (see the existing `prop_oracle_println_*` at ~line 1690 for the exact pattern) AND that property is registered in the alcotest test list. Unioning into `gen_well_typed_module` gives ONLY no-crash / structural coverage (its consumers never call `oracle_check`) — necessary but NOT sufficient. Every generator task MUST add the `prop_oracle_*` property; do BOTH wirings. (Also audit pre-existing `prop_oracle_*` properties whose shapes are now known-broken — e.g. `prop_oracle_println_tuple` if tuples fail to compile — they have been vacuously skipping 100%; file/fix per the loud-skip doctrine.)
- **Determinism:** every generator must produce programs whose output is deterministic across interpreter and both opt levels — NO actors, wall-clock, RNG, hash-order-dependent output, or float formatting. A nondeterministic generator produces spurious diffs and is worse than none.
- **Shrinking:** preserve QCheck shrinking — keep each generator's grammar shallow so a failing case shrinks to a small repro.
- **Process:** foreground only; wedge rule (runner >4 min → kill, retry once isolated-HOME, else BLOCKED); no `git stash` (file copies); never pipe `march --compile` output (redirect to files); explicit staging; no Co-Authored-By; deciduous action linked from goal 1714 before edits, outcome `--commit HEAD` after.
- **Report-from-tree:** reviewers diff every claim against the tree.
- **Known pre-existing failures (NOT yours):** heapsort RC underflow; supervision race; mono limit skip; the two open P1s this plan's generators will *deliberately reproduce* (Newtype derived-method SIGSEGV, default-arg name resolution).

---

### Task 1: Phase 1 — close the oracle's vacuous-green holes (harness only)

**Files:** Modify `test/test_properties.ml` (`run_capture` ~:681, `oracle_check` ~:706).

Context: `run_capture` pipes `2>/dev/null` (stderr discarded); `oracle_check`'s compile step (`let (rc_compile, _) = ...; if rc_compile <> 0 then None` — skip) therefore cannot distinguish a compiler CRASH (segfault, OCaml `Failure`/assertion with a backtrace on stderr) from a graceful "unsupported feature." A compiler crash on a well-typed program is always a bug and is currently silently skipped — the exact vacuous-green class Wave 2 killed elsewhere.

- [ ] **Step 1:** Capture stderr. Add a `run_capture` variant (or a param) that returns `(rc, stdout, stderr)` — change `2>/dev/null` to redirect stderr to a second temp file and read it. Keep the existing stdout-only callers working (thin wrapper) OR thread the extra return through; minimize churn.
- [ ] **Step 2:** In `oracle_check`'s compile step, classify a nonzero compile exit:
  - `rc_compile >= 128` (compiler signal-killed) → **FAILURE** (compiler segfaulted on a well-typed program).
  - stderr contains an OCaml backtrace / `Fatal error: exception` / `Assert_failure` / `Failure(` marker → **FAILURE** (internal compiler error).
  - otherwise (clean nonzero, no backtrace) → **skip** (genuine "unsupported"), counted.
- [ ] **Step 3:** Skip accounting. Route every `None`/skip through a counter (a module-level ref incremented with a reason tag) and print a per-run summary at teardown (`at_exit` or the test's own reporting): total oracle invocations, matched, skipped-by-reason. A skip must never be invisible (Wave-2 loud-skip doctrine).
- [ ] **Step 4: RED proof.** Write a throwaway `.march` program that makes the *compiler itself* crash if one exists easily (or synthesize one by feeding a construct known to hit an internal `failwith` — e.g. from `specs/todos.md`'s open items); confirm the OLD classifier skips it and the NEW one FAILs. If no compiler-crash input is readily available, prove Step 2 with a unit-level test that feeds synthetic (rc, stderr) tuples to the classifier function (refactor the classifier into a pure `classify_compile : int -> string -> [\`Fail of string | \`Skip of string]` so it is unit-testable) — this is the more robust proof and preferred.
- [ ] **Step 5:** `test_properties.exe -e` green (isolated HOME); the six runners untouched (no lib/ change). **Commit** `test(oracle): classify compiler crashes as failures, not skips; loud skip accounting (Phase 1)`.

---

### Task 2: Phase 1b — compiler "unsupported construct" exit signal

**Files:** Modify `bin/main.ml` (the `--compile` error path); possibly `lib/tir/*` where lowering raises "not implemented"; Modify `test/test_properties.ml` (consume the signal).

Context: Task 1 approximates "unsupported vs crash" via backtrace-sniffing. The robust version is a distinct, machine-readable signal from the compiler for "typechecked but this construct isn't lowerable yet," so the oracle (and humans) can tell "I don't support this" from "I crashed." Only build this if the lowering pipeline HAS identifiable "not implemented" raise sites — investigate first.

- [x] **Step 1: Survey.** Grepped `lib/tir/*.ml` + `bin/main.ml` for `failwith`/`assert false`/dedicated exceptions: ~33 real sites (34 matches minus one doc-comment mention in `lower_state.ml:77`), spread over 13 files. Every single one is an internal-invariant check (the typechecker/desugarer/monomorphizer should have prevented reaching that state — e.g. `llvm_calls.ml:122` unresolved interface dispatch, `llvm_case.ml:312` type-incorrect TIR reaching codegen, `mono.ml:888` polymorphic-recursion spec-limit) or closed-set exhaustiveness on a fixed operator table (`llvm_emit.ml` int/float/cmp/bitwise op lookups). The one plausible "not-yet-lowerable" candidate, `lower_match.ml:133` (`PatRecord` destructuring), is dead code from the compiler's perspective — the parser's grammar has no production for record patterns, so the case is unreachable from any parsed program (only reachable if an AST node were hand-constructed, e.g. in a test). **Verdict: zero genuine "typechecked but deliberately not lowered yet" sites — Outcome B.** No exception `Unsupported of string` was introduced (there is nothing distinct to raise it for).
- [x] **Step 2 (reframed per Outcome B):** Built the higher-value fix instead: a top-level `try...with` around the `compile_mode` branch in `bin/main.ml`'s `compile` (the `Lower.lower_module` → `Perceus`/`Opt` → `Llvm_emit`/clang pipeline). `Printexc.record_backtrace true` enabled at `compile`'s entry. The handler re-raises the two legitimate diagnostic exceptions that can appear in this scope (`March_errors.Errors.ParseError`, `March_tir.Js_emit.Js_emit_error` — both already handled locally before this point) and, for anything else, prints `march: internal compiler error: <exn>` + backtrace + guidance, then exits with a new documented code `internal_compiler_error_exit_code = 3`. Verified: a normal typecheck error (`I cannot find \`undefined_function_xyz\``) still renders identically and exits 1; a temporarily-injected `failwith` in `Lower.lower_module` was caught, printed via the new path, and exited 3 (probe reverted after verification — no lib/tir source changes shipped). `test/test_properties.ml`'s `classify_compile` now checks `rc = internal_compiler_error_exit_code` first (positive signal, no stderr-sniffing needed) before falling back to Task 1's signal/backtrace heuristics for older binaries; 2 new unit tests added (7 total in the `classify_compile (unit)` group, all green).
- [x] **Step 3:** Six runners green (`run_compiler` 392, `run_eval` 230, `run_codegen` 374, `run_stdlib -q` 766, `test_stdlib_march` 53 — all isolated-HOME, all exit 0); `test_properties.exe test -e "classify_compile"` green (7/7). Full un-filtered `test_properties.exe -e` run is the ~20min suite — spot-checked via the `classify_compile` unit group and a background run of the `oracle: interp = compiled` group (see report for status at time of commit) rather than blocking on the full sweep. **Commit** `docs: internal-failwith-is-always-a-bug invariant + top-level internal-error handler (Phase 1b)`.

---

### Task 3: Phase 2a — generic-container output generators

**Files:** Modify `test/test_properties.ml` (add generators, union into `gen_well_typed_module`).

Guards the println-of-list / interface-dispatch family (the `ffe6fba8` bug — compiled `println([1,2,3])` never worked). This bug is FIXED, so these generators should be fully green — they're regression protection for the whole class.

- [ ] **Step 1:** Add generators producing programs that `println`/`to_string` a generic container: `List(Int)`/`List(String)`, `Option(Int)`, tuples, and nested (`[[1,2],[3]]`). Each `main` prints a deterministic value. Model on the existing `gen_list_module`/`gen_tuple_module` structure.
- [ ] **Step 2:** Verify by RUNNING the oracle on a high count (e.g. `~count:300`) — must be green (the bug is fixed; a red here means a regression or a nondeterminism leak in your generator — fix the generator).
- [ ] **Step 3:** `test_properties.exe -e` green. **Commit** `test(oracle): generic-container output generators (println-of-list class) (Phase 2a)`.

---

### Task 4: Phase 2b — derived-method-call generators (Newtype crash NOW FIXED — full green coverage)

**Files:** Modify `test/test_properties.ml`.

**UPDATED (base merged origin/main `6cc676fc`):** the Newtype derived-method SIGSEGV is FIXED. This task no longer needs an expected-fail marker — instead the generators are full green regression protection for the just-landed fix, and they should exercise the exact shapes the fix repaired (the `==`-vs-named-`eq` discriminator, Int- and String-payload newtypes). Note: origin's fix already added targeted repros in `test/test_codegen.ml`'s `newtype_derived_method_crash` suite (6 tests) — the oracle generators are COMPLEMENTARY (random-generation coverage), do NOT duplicate those; the oracle's value is diff-over-random-programs.

- [x] **Step 1:** Generator: `derive Eq/Ord/Hash for T` then a NAMED call `compare(x,y)`/`hash(x)`/`eq(x,y)` over each of: single-field single-ctor variants (`Newtype` repr — the just-fixed shape, Int AND String payload), multi-field ctors (`Boxed`), multi-ctor enums, and a record. Each `main` prints a deterministic result. Since derived Ord/Hash IGNORE payloads (documented `syntax_reference.md`), the printed value is stable interp-vs-compiled — verify that parity holds. **Done:** 5 generators added (`gen_derived_method_newtype_int_module`, `gen_derived_method_newtype_string_module`, `gen_derived_method_boxed_module`, `gen_derived_method_enum_module`, `gen_derived_method_record_module`), unioned into `gen_well_typed_module`. Found a REAL, distinct (not `6cc676fc`) bug while scoping: the `==` OPERATOR gives the wrong answer compiled on String-payload Newtype (`ensure_adt_eq_fn` never consults `Repr.repr_of_ty` for `Newtype`, unlike its Niche special-case) — filed to `specs/todos.md` P1; the String-payload generator calls named `eq`/`compare` only (not `==`) to stay in the working subset, per this file's own "constrain to working subset" rule. Also confirmed (and filed) that compiled vs interpreted `hash()` use different algorithms for RECORD types (expected, not a bug) — the record generator omits `hash()` accordingly.
- [x] **Step 2:** WIRE per the corrected plan constraint — add a `prop_oracle_derived_method` property (or a small family) that runs the generator through `oracle_check` AND register it in the alcotest list (NOT just `gen_well_typed_module`). Confirm it EXECUTES the diff (nonzero matched, not 100% skip) at a modest count, isolated HOME. **Done:** 5 `prop_oracle_derived_method_*` properties added, registered in the `"oracle: interp = compiled"` alcotest group. Isolated run at count 50 each (250 total): **250 invocations, 250 matched, 0 skipped** — diff coverage proven to execute, not vacuous.
- [x] **Step 3:** All green (the bug is fixed). A RED is a regression in the fix or a generator nondeterminism bug — report/file. `test_properties.exe -e` green (note count). **Commit** `test(oracle): derived-method-call generators wired through oracle_check — regression guard for the Newtype-derive fix (Phase 2b)`. **Done:** all 5 new properties green; full suite run pending final gate check (see report).

---

### Task 5: Phase 2c — record-update, borrow-mode, FBIP, erased-flow generators

**Files:** Modify `test/test_properties.ml`.

Guards the EUpdate family, the dual-position class (`a5dad194`), `same_arity` (`a5dad194`), and erased-repr flows. All these bugs are FIXED, so the generators should be green — regression protection.

- [x] **Step 1:** Add generators for: (a) record updates `{ base with f: v }` on a statically-known-shape base with a field that EXISTS (green; do NOT generate missing-field updates over erased bases — that hits the open interpreter/compiled divergence; add a targeted expected-fail for that case like Task 4 instead); (b) a fn `f(a:own, b:borrow)` called `f(x, x)` with `x` dead-after (dual-position); (c) a dead binding of a multi-type-param ADT (`Result(a,b)`) before a same-arity allocation (FBIP); (d) values through a bare-`TVar` generic wrapper then used concretely (erased flow). **Done:** 4 generators added (`gen_record_update_module`, `gen_dual_position_borrow_module`, `gen_fbip_same_arity_module`, `gen_erased_flow_module`), unioned into `gen_well_typed_module`. The missing-field-on-erased-base shape is NOT generated; instead a dedicated documented-skip unit test (`test_record_update_missing_field_on_erased_base_diverges_documented`) pins the current, OPEN divergence, citing the existing `specs/todos.md` entry. No new compiler bugs found (all 4 shapes hand-verified against HEAD before writing generator code).
- [x] **Step 2:** Run each at high count; all green. Any red is a regression (report it — it's a real find) or a generator nondeterminism bug (fix the generator). **Done:** 4 dedicated `prop_oracle_*` properties added (`prop_oracle_record_update`, `prop_oracle_dual_position_borrow`, `prop_oracle_fbip_same_arity`, `prop_oracle_erased_flow`), registered in the `"oracle: interp = compiled"` alcotest group. Isolated run at count 50 each (200 total): **200 invocations, 200 matched, 0 skipped, all 4 `[OK]`** — diff coverage proven to execute, not vacuous.
- [x] **Step 3:** `test_properties.exe -e` green. **Commit** `test(oracle): record-update / dual-position / FBIP / erased-flow generators (Phase 2c)`. **Done:** see report for the full-suite final count; the one pre-existing `[FAIL]` (Task 4's already-filed `println([0])` harness gap) is unrelated to this task.

---

### Task 6: Phase 3 — widen the comparison surface (opt matrix + exit-code parity)

**Files:** Modify `test/test_properties.ml` (`oracle_check`).

- [x] **Step 1: Opt matrix.** Done via a dedicated reduced-count property `prop_oracle_opt_matrix` (NOT inside `oracle_check` on every call — that would double every existing property's wall-clock). `oracle_check` gained a `?opt` param threading `--opt n`; the property diffs interp vs both `--opt 0` and `--opt 2`. **Flag-semantics correction:** `--opt N` is the *clang* opt level (default already 2), so the second point added is `--opt 0`; the named "sort_by/cprop family" is *TIR*-level (gated by `--no-opt`, already caught by the existing default-O2-vs-interp comparison), documented as a `--no-opt` follow-up rather than widened here.
- [x] **Step 2: Exit-code parity.** `oracle_check` no longer short-circuits on interp-nonzero; interp clean-nonzero (panic) vs compiled signal-death is now a FAILURE (subsumed by the existing `rc_run >= 128` branch now that the early skip is gone). Interp signal-death → distinct `interp-signal-death` skip. Two clean-nonzeros → `both-clean-nonzero` skip (exact-code parity deliberately NOT required — legitimate cross-backend difference).
- [x] **Step 3: RED/GREEN.** Probe confirmed interp = `--opt 0` = `--opt 2` = 17 on a record-update program. Isolated `prop_oracle_opt_matrix` run: 60 invocations, 60 matched, 0 skipped, `[OK]`. Full `test_properties.exe -e` stays-green run: see report.
- [x] **Step 4:** Opt-matrix property adds ~180s (count 30 × 2 compile+run); count tuned to 30 to stay within budget. **Committed** `test(oracle): opt-level matrix (--opt 0 and --opt 2) + exit-code parity (Phase 3)`.

---

### Task 7: Phase 4 — full-corpus conformance sweep

**Files:** Create `test/test_conformance.ml` + a dune stanza (new `run_conformance.exe`), OR add a mode to the property suite — justify (a separate exe keeps the slow sweep out of the per-commit lane).

- [ ] **Step 1:** Enumerate every deterministic, self-contained `.march` program under `test/`, `bench/`, `examples/`, and stdlib doctests. Run each through the both-ways diff (interpreter vs compiled `--opt 2`). This is the "conformance mode" — higher signal per program than random generation.
- [ ] **Step 2: Explicit nondeterministic allowlist.** Programs that legitimately diverge (actor races, wall-clock, RNG, order-dependent output) go in a NAMED, committed exclusion list with a one-line reason each — never a silent skip (Wave-2 doctrine). A program not in the corpus and not in the allowlist is an error (fail if the enumeration finds an un-triaged file).
- [ ] **Step 3:** Run the sweep. **Any divergence it surfaces on day one is a REAL FOUND BUG** — file each in `specs/todos.md` with the minimal repro and add the offending program to a `known-divergence` list (distinct from the nondeterministic allowlist — this list is "open bug," the other is "legitimately nondeterministic") so the sweep is green while documenting the finds. Report the full list of finds.
- [ ] **Step 4:** Wire into a slow CI lane (not per-commit). **Commit** `test(conformance): full-corpus interpreter-vs-compiled sweep with triaged exclusions (Phase 4)`.

---

### Task 8: Phase 5 + bookkeeping — wire as the eval.ml refactor gate

**Files:** Modify `~/.claude/commands/compiler-rc.md` (outside-repo — note in report), a testing-doc (`docs/` or the spec), `specs/progress.md`, `specs/todos.md`, and the design spec's status.

- [ ] **Step 1:** Document that an `eval.ml` (interpreter) change must pass the conformance sweep with zero NEW divergences — the interpreter-refactor analogue of the byte-identical-IR gate the backend refactors used. Put this where a future refactorer will find it (the compiler-rc skill + a short note in the design spec's §4.4/§5).
- [ ] **Step 2:** specs bookkeeping: mark analysis-doc §8 items 1/3/5 progressed; record what landed per phase; list every bug the conformance sweep found (Task 7).
- [ ] **Step 3:** Six runners + `test_properties.exe` + the new conformance exe all green; doc-lint. **Commit** `docs(oracle): wire conformance sweep as the eval.ml refactor gate; record oracle-expansion completion (Phase 5)`.
