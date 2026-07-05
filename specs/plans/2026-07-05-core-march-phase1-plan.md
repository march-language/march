# Core March Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the descriptive **Core March** reference (Level 1 for the
core language) — widen the walking-skeleton fragment
(`specs/lang/core-march.md`) to the full desugared-AST core, one construct group
at a time, each anchored by golden conformance programs; consolidate into one
versioned reference; then make `eval.ml`'s core reduction loop *visibly
implement* the rules, gated by the `@oracle` sweep.

**Architecture:** Replicate the proven skeleton template — **grammar** (from
`Ast.expr`/`pattern`/`literal`) → **surface→core desugaring map** (from
`desugar.ml`, cited) → **big-step operational rules** (arm-for-arm from
`eval.ml`, cited by line) → **golden corpus** verified interpreter == compiled —
for each remaining core construct group. Every golden program lands in
`specs/lang/golden/`, which the `@oracle` sweep (`test/test_oracle.ml`) already
enumerates, so the anchor is CI-gated from the first task. The final task turns
`eval.ml`'s core arms into a delineated, spec-cross-referenced unit.

**Tech Stack:** Markdown spec + `.march` golden programs + `@oracle`
(`test/test_oracle.ml`) as the mechanical check; `lib/eval/eval.ml`,
`lib/desugar/desugar.ml`, `lib/ast/ast.ml` as the extraction sources.

## Global Constraints

- **Base:** `8a7d23ac` (== `origin/main` at plan time, contains the skeleton +
  `@oracle` wiring). Worktree ONLY:
  `/Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3`.
- **The template is `specs/lang/core-march.md`.** Every construct-group task
  produces the same four layers in the same style. Do NOT re-invent the format;
  read the skeleton first and extend it.
- **Faithfulness is the whole point.** Every operational rule MUST cite the
  `eval.ml` line(s) it is transcribed from. The rules are human-reviewed; the
  golden corpus is the mechanical anchor. A rule with no citation is a defect.
- **`@oracle` must stay GREEN (exit 0) at every commit.** Each task's golden
  programs must MATCH interpreter == compiled, OR the divergence is triaged:
  either it is a **real compiler bug** (file it in `specs/todos.md`, add to
  `known_divergence` in `test_oracle.ml`, and — if it is a *semantics* question,
  not just a codegen bug — adjudicate it per the roadmap §4.4) or it is a **spec
  error** (fix the rule). Never redden CI; never hide a divergence in the
  nondeterministic allowlist.
- **Golden naming:** continue the `gNN_<feature>.march` scheme in
  `specs/lang/golden/`; keep each program small, deterministic, and print-driven
  (observation via `println`/`int_to_string`/`bool_to_string`/`to_string`, which
  are opaque observation primitives, not core constructs). Run the committed
  `specs/lang/golden/verify.sh` (or the `@oracle` exe) as the per-task check.
- **Deferred — NOT Phase 1** (out of the core; each is its own later slice):
  effects/IO ordering, actors/`spawn`/`send`, refinements, capabilities, the
  Perceus RC discipline, session types, sigils, `EPipe`/`EAnnot`/`EHole`/`EDbg`
  (mostly desugared away or tooling-only).
- **Adjudication queue (roadmap §4.4):** the known interpreter-vs-compiled
  divergences the fragment will reach — `ERecordUpdate` on a missing field
  (Task 3), `to_string`/`show` on containers, `==`/`hash` on `Newtype`/records.
  When a slice reaches one, that is a *semantic decision point*, handled in that
  task, not a place to redden CI.
- **Process:** foreground only; the `@oracle` sweep is the gate — run it isolated
  (`HOME=$PWD/.oraclehome MARCH_BIN=$PWD/_build/default/bin/main.exe ./_build/default/test/test_oracle.exe`,
  redirect to a file, ~2–3 min). Any task touching `lib/`/`bin/` (only Task 3's
  possible fix and Task 9) must also keep the six standard runners green. No
  `git stash`; explicit staging; no Co-Authored-By.

---

### Task 1: Literals + the full primitive δ-rules

**Files:** Modify `specs/lang/core-march.md` (§2 grammar, §4.4 δ-rules); Create
`specs/lang/golden/g09_*`…`g1x_*.march`.

**Constructs:** the remaining literals (`LitFloat`, `LitString`, `LitAtom`) and
the full primitive operator set beyond `+`/`==`: arithmetic (`-`, `*`, `/`,
`mod`), the comparison family (`!=`, `<`, `<=`, `>`, `>=`), boolean ops
(`and`/`or`/`not` — confirm their surface form and whether they short-circuit in
`eval.ml`, which is a real semantic fact to pin), and string concat (`++`) if it
is a core builtin.

**Extraction:** `eval.ml` `arith_num`/`cmp_op` and the bool ops (~`:850`–`895`),
the builtin table (~`:2762`–`2810`), `match_pattern` `PatLit` for the new literal
kinds (~`:777`). Confirm and cite whether `and`/`or` are builtins (strict) or
special forms (short-circuit) — do not guess.

**Deliverable:** extend §2's `literal`/`value` grammar; add a complete δ-rule
table in §4.4 for every core primitive, each citing its `eval.ml` line and its
Int/Float/Bool/String type restriction; ≥4 golden programs exercising the new
literals and each operator family. Commit `docs(spec): Core March literals +
full primitive delta-rules`.

---

### Task 2: Tuples

**Files:** Modify `specs/lang/core-march.md`; Create golden `gNN_tuple*.march`.

**Constructs:** `ETuple` (construction), `PatTuple` (destructuring), the `VTuple`
value.

**Extraction:** `eval.ml` `ETuple` eval arm + `match_pattern` `PatTuple`
(~`:823`); `desugar.ml` (`ETuple` is identity modulo recursion — confirm + cite).

**Deliverable:** grammar + desugar-map rows + a big-step rule for tuple
construction (left-to-right, cite) and a `match(PatTuple …, VTuple …)` matching
rule (arity check + componentwise, cite); ≥3 golden programs (construct,
destructure in `let` and in `match`, nested). Commit `docs(spec): Core March tuples`.

---

### Task 3: Records (+ the missing-field adjudication) — HIGH VALUE

**Files:** Modify `specs/lang/core-march.md`; possibly `lib/eval/eval.ml`
(adjudication fix); `specs/todos.md`; Create golden `gNN_record*.march`.

**Constructs:** `ERecord` (literal), `EField` (access), `ERecordUpdate`
(functional update), `PatRecord`, the `VRecord` value.

**Extraction:** `eval.ml` `ERecord`/`EField`/`ERecordUpdate` eval arms +
`match_pattern` `PatRecord` (~`:807`).

**The adjudication (the reason this task is high value):** `{ base with f: v }`
on a field ABSENT from the base's actual shape currently **diverges** — the
interpreter silently fabricates the field, the compiled backend panics
(`specs/todos.md` "Interpreter/compiled divergence: `ERecordUpdate` on a missing
field"). Phase 1 must **decide the normative semantics** here, because you cannot
write one operational rule for `ERecordUpdate` while the two backends disagree.
The roadmap and the existing todo both recommend the *compiled* behavior (fail
loudly on an unknown field) as the safer contract. This task:
1. States the decided rule in §4 (update fails iff the field is absent).
2. Makes `eval.ml`'s `ERecordUpdate` **fail loudly on an unknown field** to
   match, so the two backends converge (then the six runners must stay green,
   and the `known_divergence` entry + todo are removed).
3. Adds a golden program for the now-converged missing-field case (both error) —
   OR, if reconciliation proves larger than this slice, pins the *decided* rule
   in the spec, keeps the golden generator away from the divergent shape, and
   files the reconciliation as a scoped follow-up (do NOT redden `@oracle`).

**Deliverable:** the record grammar/desugar/rules (construction L-to-R, field
access, the adjudicated update rule, `PatRecord` matching — note `PatRecord`
matches a subset of fields, cite `:807`); the adjudication carried out or scoped;
≥4 golden programs. Commit `docs(spec): Core March records + ERecordUpdate missing-field adjudication`.

---

### Task 4: Atoms (tagged values)

**Files:** Modify `specs/lang/core-march.md`; Create golden `gNN_atom*.march`.

**Constructs:** `EAtom` (`:ok`, `:error(x)`), `PatAtom`, `LitAtom`, the `VAtom`
value — and the `VAtom`/`VCon` interplay (a payload-carrying atom matches a
`VCon`, per `match_pattern`'s `PatAtom` arms ~`:797`–`:803`).

**Extraction:** `eval.ml` `EAtom` eval arm + `match_pattern` `PatAtom` (both the
nullary `VAtom` and the payload `VCon` cases — cite both).

**Deliverable:** grammar + rules for nullary and payload atoms, including the
documented `VAtom`↔`VCon` matching (a genuinely non-obvious fact worth pinning);
≥3 golden programs (nullary atom, payload atom, atom in `match`). Commit
`docs(spec): Core March atoms`.

---

### Task 5: Full pattern language + guards + exhaustiveness

**Files:** Modify `specs/lang/core-march.md` (unify §4.3); Create golden
`gNN_pattern*.march`.

**Constructs:** the remaining patterns — `PatAs` (`p as x`), arbitrarily nested
patterns — plus **guards** (`branch_guard`) and the **non-exhaustive-match**
semantics (`Match_failure`).

**Extraction:** `eval.ml` `match_pattern` `PatAs` (~`:830`), `match_list`
(~`:832`), and `eval_match`'s guard evaluation + first-match-wins + no-match
`Match_failure` (~`:7303`–`:7330`).

**Deliverable:** consolidate §4.3 into the complete matching relation over ALL
core patterns; add the guard rule (guard evaluated in the pattern-extended env,
must be `VBool`; a false guard falls through — cite) and the exhaustiveness rule
(no branch matches ⇒ `Match_failure`); ≥4 golden programs (as-pattern, nested
constructor+tuple, guarded branch that falls through, deliberate catch-all).
Commit `docs(spec): Core March full pattern language + guards`.

---

### Task 6: Local recursive functions

**Files:** Modify `specs/lang/core-march.md`; Create golden `gNN_letfn*.march`.

**Constructs:** `ELetFn` (`fn go(params) do … end` inside a block — a local
*recursive* function), the fixpoint/self-reference semantics.

**Extraction:** `eval.ml` `eval_block`'s `ELetFn` arm (~`:6875`) — the `env_ref`
back-patch trick that lets the closure call itself. This is the one place the
otherwise-persistent environment uses a mutable ref; the rule must capture the
recursive knot faithfully (a `VBuiltin` wrapper whose body re-reads the extended
env — cite exactly).

**Deliverable:** grammar + a big-step rule for `ELetFn` that binds the name to a
self-referential closure in the block's continuation env; ≥3 golden programs
(recursive factorial/countdown, mutual-ish via nesting, a local fn closing over
an outer binding). Commit `docs(spec): Core March local recursive functions`.

---

### Task 7: Boolean conditionals (`ECond`) + fold in `EIf`

**Files:** Modify `specs/lang/core-march.md`; Create golden `gNN_cond*.march`.

**Constructs:** `ECond` (the `match do cond_arm* end` boolean chain) and the
already-specified `EIf` (fold the skeleton's `EIf` rules into the unified
conditionals section).

**Extraction:** `eval.ml` `ECond` eval arm (find it; cite) — confirm arm order
(first true wins) and the no-arm-true behavior.

**Deliverable:** grammar + rules for `ECond` (evaluate arm conditions top-to-
bottom, first `VBool true` selects its body; pin the all-false behavior);
cross-reference `EIf`; ≥2 golden programs. Commit `docs(spec): Core March boolean conditionals`.

---

### Task 8: Consolidate into the unified Core March reference

**Files:** Modify `specs/lang/core-march.md` (restructure from "skeleton" to
"reference"); Create `specs/lang/golden/INDEX.md` (golden → rule map).

No new semantics — assembly and versioning. Merge the per-group additions into a
single coherent document: one complete grammar (§2), one desugar-map table (§3),
one operational-rule set grouped by construct (§4) with every `eval.ml` citation,
and a golden index mapping each program to the rule(s) it anchors. Restate the
status header from "walking skeleton v0" to "Core March reference v1 (core
fragment complete)"; carry forward the §4.6 faithfulness caveat and the §6
deferred-list (now the roadmap's Phase-2/3 queue). Commit `docs(spec): consolidate Core March reference v1`.

---

### Task 9: `eval.ml` core-loop legibility refactor (oracle-gated)

**Files:** Modify `lib/eval/eval.ml`; Modify `specs/lang/core-march.md` (add the
code cross-reference note).

**Scope — legibility, NOT rewrite.** `eval_expr` already evaluates the core
arm-for-arm; this task makes that correspondence *explicit and durable*: (1) group
the core-construct arms into a clearly delineated section (or a well-named
`eval_core` helper) with a header comment stating "this is the operational
semantics of Core March — see `specs/lang/core-march.md` §4"; (2) annotate each
core arm with its rule name (`(* E-App-Clo — core-march.md §4.2 *)` etc.);
(3) do NOT change behavior. A deeper structural rewrite (if ever wanted) is a
separate Phase-1b plan.

**Gate:** this is the interpreter-refactor analogue of the byte-identical-IR
gate — the `@oracle` sweep is what certifies behavior preservation. Run the full
`@oracle` sweep (must stay exit 0, zero new divergences) AND the six standard
runners (`run_compiler`/`run_eval`/`run_codegen`/`run_stdlib`/`test_stdlib_march`/
`run_snapshots`, all green — this is the one spec-track task that touches
`eval.ml`, so interpreter tests must confirm no behavior drift). Commit
`refactor(eval): delineate + cross-reference the Core March core reduction loop (oracle-gated)`.

---

### Task 10: Bookkeeping + Phase-1 closeout

**Files:** Modify `specs/progress.md`, `specs/todos.md`,
`specs/2026-07-04-language-specification-roadmap-design.md`.

Record what landed: the Core March reference v1 (core fragment complete), the
golden corpus count, any adjudicated divergence (Task 3), the deferred groups as
the Phase-2/3 queue. Mark the roadmap's Phase 1 status. Final gate: full
`@oracle` sweep exit 0 + six runners green + doc-lint. Commit
`docs: Core March Phase 1 complete — reference v1 + closeout`.

---

## Self-review notes

- **Spec coverage:** Tasks 1–7 cover every core `Ast.expr`/`pattern`/`literal`
  constructor the interpreter runs and desugar leaves in the core (cross-check
  against `ast.ml:32`–`110`), minus the explicitly deferred set. Task 8
  consolidates; Task 9 makes it normative-by-cross-reference; Task 10 closes out.
- **Sequencing:** literals/primitives first (everything uses them), then the
  compound values (tuples, records, atoms), then the pattern/guard machinery that
  destructures them, then local recursion and conditionals, then consolidate,
  then the code refactor (which must come last — it cross-references the whole
  finished spec).
- **Risk:** Task 3 (records) is the only spec task that may touch `lib/` (the
  adjudication fix) and Task 9 touches `eval.ml`; both are `@oracle`- and
  six-runner-gated. Tasks 1,2,4–8 are docs + golden programs only.
