# March Language Specification — Roadmap Design Spec

**Date:** 2026-07-04
**Status:** Design — not yet scheduled
**Author:** follow-up to the differential-oracle expansion (PR #10).
**Depends on:** `specs/2026-07-04-differential-oracle-design.md` (built — the
consistency oracle and the `@oracle` conformance sweep are the foundation this
plan stands on), `specs/lean4-metatheory-plan.md` (the Level-3 mechanization
feasibility study).

---

## 1. Problem

March has no single normative specification. What it has instead:

- The **interpreter** (`lib/eval/eval.ml`, ~9,000 lines) *is* the de-facto
  semantics — it defines what every program means.
- The **grammar** lives only in `lib/parser/parser.mly` (with 59 shift/reduce
  conflicts resolved arbitrarily, contradicting the grammar's own header).
- The **type system** is 8,000 lines of algorithmic `lib/typecheck/typecheck.ml`.
- **Documentation** is prose that rots: Wave 4 found `syntax_reference.md` was
  factually wrong about `if`/`then`, and several load-bearing behaviors
  (top-level-`let` re-evaluation, the newline-glom continuation rule, derived
  `Ord`/`Hash` ignoring payloads) were folklore discovered only by probing.

The problem is not that there is no semantics — it is that the semantics is
tens of thousands of lines of OCaml nobody can read *as a specification*, and no
artifact says authoritatively what a program is *supposed* to do (as opposed to
what the current implementation happens to do).

## 2. The target — spec levels

A "proper spec" is ambiguous; name the levels so we can pick one:

- **Level 0 (today):** the implementation *is* the spec; no normative artifact.
- **Level 1 — descriptive reference:** a written, versioned syntax + semantics
  reference, kept honest by tests. What Python/Go actually ship.
- **Level 2 — conformance-tested:** every claim in the reference is backed by a
  runnable test. The differential oracle + a golden conformance corpus gets most
  of the way here.
- **Level 3 — formal semantics:** mathematical operational/typing rules, possibly
  mechanized (Lean 4 — see `specs/lean4-metatheory-plan.md`).
- **Level 4 — spec-derived implementation:** an implementation extracted from or
  checked against the formal spec.

**Realistic goal: Level 1–2 for the whole language, Level 3 for the fragments
that pay** (the RC/FBIP discipline and the type system). A full Level-3/4
formalization of all of March (HM + refinements + capabilities + effects + RC +
actors + a compiled backend) is a multi-person-year research project, and most
of the value sits below that line. Do not try to jump the whole language to
Level 3.

## 3. The two assets we already have

The work is *not* starting from zero — two existing assets carry most of the
weight, and the second was just built:

1. **The interpreter is an executable operational semantics.** It is the
   reference oracle: it already defines what programs mean. The problem is
   legibility, not absence.
2. **The differential oracle is a consistency spec (built — PR #10).** The
   property oracle (`test/test_properties.ml`) and the `@oracle` conformance
   sweep (`test/test_oracle.ml`) pin **"interpreter output == compiled output"**
   across both backends. That is *half* a spec: it does not say what the
   behavior *is*, but it makes any behavior we *do* write down testable against
   both implementations simultaneously, and it already turned up real
   divergences (a DataFrame RC-misclassification P0; `==`-on-`Newtype`; the
   `to_string`-on-container and sort-RC families).

So the work is: **make the operational semantics readable and normative, and use
the oracle to keep it honest.** The oracle was the prerequisite, not a detour.

## 4. Approach

### 4.1 Extract a core calculus + document desugaring as spec

Define a small **core calculus** — the kernel the surface language desugars into:
lambda, `let`, `match`, constructors, primitives, plus the RC and effect
annotations. Then:

- **`lib/desugar/desugar.ml` already computes most of the surface→core map**
  (multi-head fns → single `match`, pipes → applications, comprehensions →
  `List.map`, `~H` → escaping, default args, `let?` → `Result` propagation).
  Documenting that desugaring *is half the surface-language spec* — the surface's
  meaning follows from "desugar to core, then run core." Behaviors that were
  folklore (top-level-`let` re-evaluation, newline-glom, derived-`Ord`) become
  *derivable* from desugaring + core rules rather than discovered by probing.
- The core is small enough to read and argue about; the surface is not.

### 4.2 Core operational semantics + `eval.ml` refactor (oracle-gated)

Write the core's operational semantics as a few pages of inference rules
(small-step preferred, per the metatheory plan's §4.4). That is the normative
heart. Then **refactor `eval.ml` so its core loop visibly implements those
rules** — the `eval.ml` split flagged as the obvious next backend-style refactor.

The payoff of PR #10 is exactly here: **`eval.ml` has no IR to diff, so the
`@oracle` conformance sweep is the only thing that can certify the refactor
preserves behavior** — the interpreter-refactor analogue of the byte-identical-IR
gate the Wave-3 backend refactors used (now documented as the `eval.ml` gate in
the `compiler-rc` skill §6). Without the oracle this refactor was unsafe; with
it, it is a gated, reviewable change.

### 4.3 Declarative typing rules + a typecheck conformance suite

Operational semantics says what runs; the **type system makes the safety
claims**, and March's is ambitious — bidirectional HM inference + refinements
(z3-discharged) + the capability lattice (`lib/caps/`) + effects. A spec needs:

- **Declarative typing rules** written down: the judgment forms (`⊢ e : τ`),
  refinement discharge, capability subsumption, effect propagation — extracted
  from `typecheck.ml`'s *algorithm* (which is not the rule set). This artifact
  exists nowhere today and is the single biggest gap.
- **A typecheck conformance suite** — "typechecks-OK / rejected-with-error-E" —
  the type-side analog of the differential oracle. The campaign found several
  typecheck/mono divergences; this is where more real bugs hide, and it does not
  exist yet.

This is harder than the operational spec and worth more. It is also where
mechanization pays first — refinement and capability soundness are exactly the
claims you want machine-checked.

### 4.4 Golden conformance corpus + divergence adjudication (Level 2)

The `@oracle` sweep certifies *consistency* (interp == compiled). Level 2
additionally needs each claim pinned to **what the behavior actually is**:

- **Golden expected-outputs**, not just cross-backend agreement — two backends
  can agree on a wrong answer. Extend the conformance corpus so each program
  carries an expected output (the interpreter is the reference, but the golden
  pins it so a *coordinated* regression is caught).
- **Adjudicate the `known_divergence` list into decided semantics.** You cannot
  conformance-test a claim you have not decided. The oracle produced the finite
  queue of undecided points (missing-field `ERecordUpdate` — interp fabricates,
  compiled panics; the `to_string`-container shape; etc.); each needs a normative
  ruling, after which the non-conforming backend is fixed to match. **The
  `known_divergence` list is the input queue for the spec's semantic decisions.**
- **Executable-docs CI:** every code block in the Level-1 reference runs as a
  test, so a doc claim with no passing test fails CI — the discipline that stops
  the `syntax_reference.md`-rots-to-wrong failure (see the executable-docs idea
  in `specs/2026-07-04-concurrent-compiler-work-design.md`).

### 4.5 Mechanize the fragments that pay (Level 3)

For the corners where informal argument is not convincing, mechanize in Lean 4
per `specs/lean4-metatheory-plan.md`. Its Phase 1 (STLC + ADTs) and Phase 2 (HM)
are the baseline; the fragments worth reaching are **Perceus RC/FBIP**
(`specs/perceus-invariants.md` is the informal version waiting to be formalized;
there is already appetite per the FBIP-mechanization interest) and **refinement /
capability soundness**. Level 3 is a longer research track that grows from the
Level-1 rules — it consumes the same core calculus and typing rules produced by
§4.1–4.3, so those are its prerequisites too.

### 4.6 Consolidate and version the existing docs

March already has ~20 `specs/features/*.md` (type-system, pattern-matching,
module-system, standard-interfaces, tir-invariants, …), `syntax_reference.md`,
`docs/value-representation.md`, and the Wave-4 semantics notes — descriptive,
uneven, un-versioned. Level 1 is unifying these into **one normative reference**
with a stated, *resolved* grammar (not the ambiguous `parser.mly`), and
**versioning it** — a spec that is not versioned-and-tested rots exactly like
`syntax_reference.md` did.

## 5. Phasing

- **Phase 0 — prerequisites: DONE.** The differential oracle + `@oracle`
  conformance sweep + the `eval.ml`-refactor gate (PR #10). You cannot spec what
  you cannot reproduce; this froze and cross-tested observable behavior and
  produced the divergence queue.
- **Phase 1 — Level-1 core (operational).** §4.1 core calculus + desugaring map,
  §4.2 core operational rules, then the oracle-gated `eval.ml` refactor. Deliver
  the core-language reference. *This is where to start* (see §9).
- **Phase 2 — Level-1 types + Level-2 conformance.** §4.3 declarative typing
  rules + typecheck conformance suite, §4.4 golden corpus + `known_divergence`
  adjudication + executable-docs CI, §4.6 consolidate/version the reference.
- **Phase 3 — Level-3 fragments.** §4.5 mechanize RC/FBIP and the
  refinement/capability type-system fragments, extending the Lean 4 baseline.

Phases 1 and 2 interleave in practice: **writing the operational and typing
rules is what forces the `known_divergence` decisions**, so §4.2/§4.3 and §4.4's
adjudication proceed together rather than strictly in sequence.

## 6. Acceptance criteria

- **Level 1:** a single versioned reference exists covering surface grammar
  (resolved), the desugaring→core map, the core operational rules, and the
  declarative typing rules; every load-bearing behavior currently in folklore is
  written down and derivable.
- **Level 2:** every claim in the reference has a runnable test; the golden
  conformance corpus asserts expected outputs (not just interp==compiled) and
  runs both backends; the `known_divergence` queue is empty (each entry either
  adjudicated + the non-conforming backend fixed, or explicitly declared
  out-of-core-scope with a reason); doc code-blocks run in CI.
- **`eval.ml` refactor:** the core loop visibly implements the operational rules,
  landed through the `@oracle` gate with zero new divergences.
- **Level 3 (fragments):** the RC/FBIP invariants (`perceus-invariants.md`) and
  the refinement/capability soundness claims are machine-checked in Lean 4.

## 7. Risks / open questions

- **Scope creep past Level 2.** The temptation is to formalize everything; most
  value is at Level 1–2. Guard the line: Level 3 only for fragments where
  informal argument has already failed (RC/FBIP, refinements).
- **The core-calculus faithfulness gap.** The core model must be a *faithful*
  subset of what `eval.ml`/`typecheck.ml` actually do, or the spec proves
  soundness of a language March isn't. The oracle is the check that keeps the
  `eval.ml` refactor faithful; there is no equivalent automatic check that the
  *paper* core rules match — that requires careful review against the
  interpreter, and is the main soundness risk of §4.1/§4.2.
- **Divergence adjudication can surface hard design questions.** Deciding the
  missing-field `ERecordUpdate` semantics (fabricate vs panic) is a *language
  design* decision, not a mechanical one — some `known_divergence` entries will
  need a human ruling, not just a bugfix.
- **Effort is assurance, not features.** Phases 1–2 are focused-waves of work
  using machinery already built (the oracle, the Wave-3 refactors, the
  claim-verification discipline, the subagent-review loop); Phase 3 is a
  research track. Sequence accordingly and do not let Phase 3 block Phase 1–2.

## 8. Relationship to existing work

- **Builds directly on the differential oracle** (`specs/2026-07-04-differential-oracle-design.md`,
  PR #10): the oracle is Phase 0, its `@oracle` sweep is the `eval.ml` gate for
  §4.2, and its `known_divergence` list is the input queue for §4.4's
  adjudication.
- **Consumes the Wave-3/4 legibility dividend.** The perceus/llvm_emit/lower
  splits, the shared-contract modules (`Tir_names`, `Rc_types`), and the Wave-4
  invariant docs (`docs/value-representation.md`, `specs/perceus-invariants.md`,
  `specs/features/tir-invariants.md`) are implementation-side invariants that are
  the *beginnings of a spec* — the refactors made the compiler legible enough
  that extracting a language spec from it is now tractable.
- **Feeds the Lean 4 metatheory** (`specs/lean4-metatheory-plan.md`): §4.1–4.3
  produce the core calculus and declarative rules that Phase 1/2 of that plan
  need as inputs; §4.5 is where the two efforts meet.
- **Shares the executable-docs discipline** with
  `specs/2026-07-04-concurrent-compiler-work-design.md` (§4.4).
- **Consolidates** the existing `specs/features/*.md`, `syntax_reference.md`, and
  the Wave-4 semantics notes into the single versioned reference (§4.6).

## 9. Recommended first artifact

Do **not** start with Lean. Start with the two prose extraction docs that Phase 1
depends on and that are valuable independently — they *are* the human-readable
spec, and writing them is what turns the oracle's `known_divergence` list into
resolved decisions:

1. **The core calculus + desugaring-as-spec map** (§4.1) — derived from
   `desugar.ml`, cross-checked against the interpreter.
2. **The core small-step operational semantics** (§4.2) — pinned as a relation
   and confirmed against `eval.ml`, then used to gate the `eval.ml` refactor.

These are the lowest-commitment, highest-leverage Phase-1 groundwork, they slot
straight into the same plan-and-execute machinery (design spec → plan →
subagent-driven execution → oracle-gated) the oracle expansion used, and they
make every subsequent phase concrete.
