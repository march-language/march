# Differential Oracle Expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `specs/2026-07-04-differential-oracle-design.md` — expand the differential oracle (`test/test_properties.ml`) so the interpreter/compiled-divergence bug class is caught in CI, and make the oracle strong enough to serve as the future `eval.ml` refactor gate.

**Architecture:** Incremental hardening of the existing QCheck2 oracle plus one small compiler change (an "unsupported construct" exit signal). Phases: (1) close the oracle's own vacuous-green holes, (2) expand generators toward the failure shapes, (3) widen the comparison surface, (4) full-corpus conformance sweep, (5) wire as the refactor gate.

**Tech Stack:** OCaml 5.3 / dune / QCheck2; the compiler at HEAD for behavior verification.

## Global Constraints

- **Base:** `c7575b06` (== main == origin/main at plan time). Worktree ONLY: `/Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3`, branch `claude/hopeful-kapitsa-9f49f3`. Controller handles the main merge at the end.
- **Build/test:** `dune build --root .`; the property exe is `test_properties.exe` (dune stanza name `test_properties`, `test/dune:297`). Run it `HOME=$PWD/.oraclehome ./_build/default/test/test_properties.exe -e` (isolated HOME — the oracle compiles many programs and is a heavy cache client; isolation avoids the shared `~/.cache/march` fake-hang). The six standard runners (`run_compiler`/`run_eval`/`run_codegen`/`run_stdlib`/`test_stdlib_march`/`run_snapshots`) must stay green for any task that touches `lib/` or `bin/`.
- **CRITICAL — the oracle must stay GREEN on `main` at every commit.** Several generators here reproduce KNOWN OPEN BUGS (the Newtype derived-method SIGSEGV; the record-update missing-field divergence). A generator that reddens CI on an unfixed bug is NOT landable. The rule: **constrain each generator to the currently-WORKING subset**, and for the broken subset add a *separate targeted test marked expected-fail / skip-with-reference* citing the open `specs/todos.md` entry — never widen a generator into a known crash. When the underlying bug is fixed, a follow-up widens the generator (note this in the task's report).
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

- [ ] **Step 1: Survey.** Grep `lib/tir/`, `bin/main.ml` for the current "not implemented"/"unsupported" raise sites (`failwith "TODO"`, `Not_implemented`, dedicated exceptions). Determine whether they're distinguishable from genuine internal errors. If they are NOT cleanly separable (unsupported and internal-error both `failwith` with no marker) — report the finding; the minimal viable change is to introduce ONE exception (`Unsupported of string`) raised at the deliberate not-yet-lowerable sites, caught in `bin/main.ml`'s `--compile` path, printed with a stable marker (e.g. `march: unsupported: <what>` to stderr) and a distinct exit code (pick an unused one, e.g. `3`, documented). If the survey shows there are effectively NO deliberate-unsupported sites (everything typechecked is lowerable), report that — this task then reduces to documenting the invariant and Task 1's backtrace-classifier is sufficient; mark Task 2 minimal/closed with the finding.
- [ ] **Step 2:** If the exit-code path is built: `oracle_check` treats the distinct code / marker as a clean skip and ANY other nonzero (esp. with a backtrace) as FAILURE — tightening Task 1's heuristic.
- [ ] **Step 3:** Six runners green (lib/bin touched); `test_properties.exe -e` green. **Commit** `feat(compile): distinct exit signal for unsupported-but-typechecked constructs; oracle consumes it (Phase 1b)` (or a docs-only commit if the survey shows it's unwarranted).

---

### Task 3: Phase 2a — generic-container output generators

**Files:** Modify `test/test_properties.ml` (add generators, union into `gen_well_typed_module`).

Guards the println-of-list / interface-dispatch family (the `ffe6fba8` bug — compiled `println([1,2,3])` never worked). This bug is FIXED, so these generators should be fully green — they're regression protection for the whole class.

- [ ] **Step 1:** Add generators producing programs that `println`/`to_string` a generic container: `List(Int)`/`List(String)`, `Option(Int)`, tuples, and nested (`[[1,2],[3]]`). Each `main` prints a deterministic value. Model on the existing `gen_list_module`/`gen_tuple_module` structure.
- [ ] **Step 2:** Verify by RUNNING the oracle on a high count (e.g. `~count:300`) — must be green (the bug is fixed; a red here means a regression or a nondeterminism leak in your generator — fix the generator).
- [ ] **Step 3:** `test_properties.exe -e` green. **Commit** `test(oracle): generic-container output generators (println-of-list class) (Phase 2a)`.

---

### Task 4: Phase 2b — derived-method-call generators (WORKING subset) + targeted expected-fail for the open crash

**Files:** Modify `test/test_properties.ml`; add a targeted test (in `test_properties.ml` or `test/test_codegen.ml` — justify).

Guards the derived-method family AND documents the OPEN Newtype SIGSEGV (`compare`/`hash`/`eq` by name crash on single-field single-ctor variants; the `==` operator works; multi-field Boxed ctors work — see `specs/todos.md` "Newtype-repr variants").

- [ ] **Step 1:** Generator (green subset): `derive Eq/Ord/Hash for T` then a NAMED call `compare(x,y)`/`hash(x)`/`eq(x,y)` where `T` is restricted to the WORKING shapes — **multi-field ctors (`Boxed` repr)** and, if verified working, multi-ctor enums. Do NOT generate single-field single-ctor (`Newtype`) variants — that path crashes. Verify the generator's output is all-green at high count.
- [ ] **Step 2:** Targeted expected-fail: add ONE explicit test that compiles+runs the Newtype-crash repro (`type Wrap = Wrap(Int); derive Ord for Wrap; ... compare(Wrap(1), Wrap(2))`) and asserts the CURRENT (buggy) behavior is a crash — marked clearly as `expected-fail`/documented-skip citing the `specs/todos.md` P1 entry, so the oracle *records* the open bug without reddening CI, and the test flips to a real assertion when the bug is fixed. (Alcotest has no native xfail; implement as a skip-with-reason that would become a hard assertion — leave a `TODO(unblock when Newtype derived-method crash fixed)` comment.)
- [ ] **Step 3:** `test_properties.exe -e` green. **Commit** `test(oracle): derived-method-call generators (Boxed subset); expected-fail marker for open Newtype crash (Phase 2b)`.

---

### Task 5: Phase 2c — record-update, borrow-mode, FBIP, erased-flow generators

**Files:** Modify `test/test_properties.ml`.

Guards the EUpdate family, the dual-position class (`a5dad194`), `same_arity` (`a5dad194`), and erased-repr flows. All these bugs are FIXED, so the generators should be green — regression protection.

- [ ] **Step 1:** Add generators for: (a) record updates `{ base with f: v }` on a statically-known-shape base with a field that EXISTS (green; do NOT generate missing-field updates over erased bases — that hits the open interpreter/compiled divergence; add a targeted expected-fail for that case like Task 4 instead); (b) a fn `f(a:own, b:borrow)` called `f(x, x)` with `x` dead-after (dual-position); (c) a dead binding of a multi-type-param ADT (`Result(a,b)`) before a same-arity allocation (FBIP); (d) values through a bare-`TVar` generic wrapper then used concretely (erased flow).
- [ ] **Step 2:** Run each at high count; all green. Any red is a regression (report it — it's a real find) or a generator nondeterminism bug (fix the generator).
- [ ] **Step 3:** `test_properties.exe -e` green. **Commit** `test(oracle): record-update / dual-position / FBIP / erased-flow generators (Phase 2c)`.

---

### Task 6: Phase 3 — widen the comparison surface (opt matrix + exit-code parity)

**Files:** Modify `test/test_properties.ml` (`oracle_check`).

- [ ] **Step 1: Opt matrix.** Run the compiled path at BOTH `--opt 0` and `--opt 2`; diff each against the interpreter. An `--opt 2`-only divergence is an optimizer miscompile (the sort_by/cprop family) that the current `--compile`-default never sees. To bound cost, run `--opt 0` at full generator count and `--opt 2` at a reduced count (justify the split; the goal is coverage, not doubling wall-clock).
- [ ] **Step 2: Exit-code parity.** When BOTH interpreter and compiled exit nonzero (currently skipped), compare the exit codes — a clean interpreter panic vs a compiled segfault on the same program is a divergence, not a mutual skip. Preserve the existing `>= 128` signal-death FAILURE logic; add: interpreter-clean-nonzero vs compiled-signal-death is a FAILURE.
- [ ] **Step 3: RED/GREEN.** Confirm the opt matrix actually compiles at both levels (a targeted probe) and that a synthetic divergence (if constructible) is caught. Full `test_properties.exe -e` green at HEAD.
- [ ] **Step 4:** Benchmark the wall-clock delta of the suite (report before/after); if it grows unacceptably, tune the opt-2 count. **Commit** `test(oracle): opt-level matrix (--opt 0 and --opt 2) + exit-code parity (Phase 3)`.

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
