# Stage A — Lean ↔ March type-system conformance bridge

> **Status: PLAN — not started. Written for an implementing agent.**
> Parent context: `specs/plans/lean4-metatheory-plan.md` (the full 35–56-week
> metatheory roadmap). **This plan is deliberately NOT that.** Stage A builds a
> *second, independent, executable type checker* in Lean and wires it as a
> differential-conformance CI gate against the OCaml compiler's `--check`
> verdicts. It is valuable on its own as bug-finding + spec-crispening, and it
> is decoupled from every soundness proof: you get the guardrail whether or not
> the checker is ever proven correct. The proofs (Stage B) later upgrade this
> same checker from "guardrail" to "theorem"; Stage A's Lean code is the object
> Stage B proves sound, so nothing here is throwaway.

---

## 0. Goal & success definition

Two independent implementations of March's type system — the production OCaml
one (`lib/typecheck/typecheck.ml`) and a new Lean one — must agree on the
accept/reject verdict for every program in `specs/lang/types/{accept,reject}`
(currently 87 accept + 81 reject = 168). A CI job runs both over the corpus and
**fails on any disagreement**. A disagreement is, by construction, either a real
bug in the OCaml type checker or a place where the Lean formalization got a rule
wrong — both are exactly what we want surfaced.

**Done when:** the conformance job is green over the full corpus, runs in CI,
and a deliberately-introduced divergence (e.g. temporarily relax one Lean rule)
turns it red.

**Non-goals (explicit):** no progress/preservation/linearity/Perceus proofs (that
is Stage B/C); no re-implementation of March's lexer/parser/desugarer in Lean
(the seam is a JSON AST — see §3); no unification-algorithm *correctness* claim
(A2 implements inference, but proving it principal is out of scope).

---

## 1. Repo decision — **separate repo** (answers "does A live in a separate repo?")

**Yes. Create a new repo `march-lean` (Lean 4 + Lake).** Do NOT put Lean/Mathlib
in the March monorepo. Rationale:

- Mathlib is a ~200k-LOC, fast-moving, version-pinned dependency with its own
  toolchain (`lean-toolchain`, a pinned Mathlib commit, the `lake exe cache get`
  prebuilt-`.olean` flow). Dragging it into the `march` repo pollutes March's
  build environment, couples March's CI to Lean's toolchain, and makes March
  contributors trip over Lean build breakage. `lean4-metatheory-plan.md` §3.2
  already frames the formalization as a standalone Lake project.
- The coupling between the two is a **data contract, not a build dependency**:
  a JSON AST format (§3) + a versioned copy of the corpus + a native binary.
  Lean 4 compiles to a self-contained native executable, so the Lean side ships
  as one prebuilt `march-lean-check` binary with no Mathlib *runtime* dep.

**Where the CI job lives (staged):**
- **Initially, in `march-lean`.** The `march-lean` repo's CI builds its own
  checker binary (Mathlib cached there), pulls (a) the corpus and (b) a pinned
  `march` binary, runs the diff. **March's CI is untouched.** This defers all
  cross-repo gating until the checker has earned it.
- **Later (optional), a non-blocking mirror job in `march` CI** that downloads a
  published `march-lean-check` release binary and runs the same diff — so a
  March PR that breaks conformance shows a signal, without Mathlib in March CI.
  Make it required only once it's proven stable.

**Corpus contract / drift management.** The corpus lives in `march` at
`specs/lang/types/`. `march-lean` pins a specific March git SHA (or consumes a
released `types-corpus.tar` artifact). When March's corpus changes, bumping the
pin in `march-lean` is a deliberate, reviewed step — that bump is *where you
notice* the type system changed and the Lean model may need updating (this is
the manual-audit discipline from metatheory-plan §8.2, but now with a red CI to
force it rather than a human remembering).

---

## 2. The shared "core level"

The corpus is deliberately a set of **small core-language witnesses** (no pipes,
interpolation, or module sugar) — see `specs/lang/types/INDEX.md`. So a
core-level checker can eat most of it directly. The seam is the **post-desugar,
pre-typecheck AST** (the value `check_module` receives) plus, for A1, the
**elaborated/type-annotated** form. Consequences:

- The Lean side does **not** re-implement lexing/parsing/desugaring. Those are
  already covered by the grammar corpus (`specs/lang/grammar`, 41 programs) and
  are syntactic/low-bug-density. Sharing March's desugar output *isolates the
  type system* as the thing under differential test — which is the bug-dense
  part (this repo's history: linearity, unification, cap-erasure, fn_arities
  poisoning).
- Any corpus program that uses a construct the Lean core doesn't model yet is
  **skipped with a loud, counted ledger entry** (never silently) — mirror the
  `[tool-skip ledger]` pattern already used in March's test suites. The set of
  skipped programs must shrink to zero for "full corpus" done; track it.

---

## 3. March-side work — the JSON AST seam

The only change needed in the **`march` repo**: emit the desugared (and, for A1,
elaborated) AST as JSON for a single input file. The JSON serialization infra
already exists — `lib/dump/dump.ml` has `json_string`/`json_obj`/`json_list`,
and there is precedent in `--check-json` (NDJSON diagnostics) and `--dump-phases`.

Add a flag `--emit-core-ast <file.march>` that runs parse → desugar →
(A1: typecheck+elaborate) and writes to stdout a JSON document:

```json
{
  "format_version": 1,
  "verdict": "accept" | "reject",         // == what `march --check` decides
  "diagnostics": [ { "severity": "...", "message": "...", "span": {...} } ],
  "module": { ...desugared AST as JSON... }, // present iff it desugared
  "elaborated": { ...type-annotated AST... } // A1 only; present iff accept
}
```

Design notes for the agent:
- Emit the AST at the SAME point `check_module` consumes it (post `qualify_module_refs`,
  post default-injection), so the Lean checker sees exactly what OCaml type-checks.
- Serialize the `Ast.expr`/`Ast.ty`/`Ast.pattern`/`Ast.decl` types faithfully.
  Keep it total: one JSON constructor per OCaml constructor, spans included.
- `verdict` MUST equal `march --check`'s accept/reject for that file (share the
  code path; don't reimplement the accept/reject decision).
- Freeze the format with a `format_version`; the Lean JSON reader keys on it.
- Add a golden test in `march` pinning the JSON for ~3 representative corpus
  files (so the seam can't silently drift). This is the ONLY new `march` surface;
  keep it minimal and documented in `specs/lang/` (its own short reference).

There is **no other `march`-side change.** The compiler does not depend on Lean.

---

## 4. Lean-side design (`march-lean`)

Lake project, Mathlib dependency, `lean-toolchain` pinned. Compile the checker
to a native binary via `lake build march-lean-check` (a Lean `main` that reads
the JSON on argv/stdin and exits 0=accept / 1=reject / 2=skip / 3=error).

Module skeleton (subset of `lean4-metatheory-plan.md` §3.1, the *executable*
slice — no `Metatheory/` proofs in Stage A):

```
march-lean/
├── lakefile.toml
├── lean-toolchain
├── MarchLeanCheck.lean            # `main`: JSON → Term → check → exit code
└── MarchLean/
    ├── Json.lean                  # JSON → core Syntax (mirrors §3's format_version 1)
    ├── Syntax/{Ty,Term,Pattern}.lean
    ├── Typing/
    │   ├── LinearContext.lean     # context split / contraction / weakening as a bag
    │   ├── TypeRules.lean         # bidirectional check/infer, DECIDABLE (returns Except)
    │   └── LinearityRules.lean    # Lin | Aff | Unr use tracking
    └── Util/{Finmap,Multiset}.lean # or Mathlib's
```

Staged milestones **within** Stage A (each independently shippable, each de-risks
the next):

### A0 — plumbing, trivial checker (target: the pipe end-to-end works)
- `march --emit-core-ast` (§3) landed with the golden.
- `march-lean` builds a `march-lean-check` binary that reads the JSON, **ignores
  the AST**, and just echoes `verdict` back as its exit code.
- Conformance harness (§5) runs both over the corpus and passes trivially (Lean
  parroting March's verdict). This proves the seam + CI + binary-publish plumbing
  before any real type-system work. **Acceptance:** CI green; the harness detects
  a hand-forced mismatch.

### A1 — elaboration checker (accept-side independence)
- Lean implements `TypeRules.check : Ctx → Term → Ty → Except Err Unit` — a pure
  *checker* over the ELABORATED (type-annotated) AST. No inference/unification.
- Verdict rule: for every `accept` program, Lean must independently CHECK
  March's elaboration under its rules (Lean-accept). Mismatch = March produced a
  rule-inconsistent elaboration OR the Lean rules are wrong.
- Includes the linearity/affinity use-counting rules (the highest-value,
  bug-dense fragment). **Acceptance:** Lean checks every non-skipped `accept`
  elaboration; skip-ledger enumerated and shrinking.

### A2 — independent inferencer (full accept/reject)
- Lean implements its own bidirectional inference + unification over the
  DESUGARED (un-annotated) AST, producing its OWN accept/reject — no reliance on
  March's elaboration. THIS is the full differential oracle: it independently
  decides the `reject` side too.
- **Acceptance:** Lean's verdict == March's verdict for every non-skipped corpus
  program; skip-ledger → 0 for the core fragment the corpus exercises.

A0/A1 are the de-risking ramp; A2 is the real prize. Ship each.

---

## 5. Conformance harness & CI

A small script (bash/Lean/OCaml — keep it dependency-light), living in
`march-lean`:

```
for f in <corpus>/accept/*.march <corpus>/reject/*.march:
    march_verdict = ( march --check f ; exit-code → accept|reject )
    json          = march --emit-core-ast f
    lean_verdict  = march-lean-check <<< json   # 0=accept 1=reject 2=skip 3=err
    record (f, march_verdict, lean_verdict)
report: mismatches (FAIL), skips (loud ledger), errors (FAIL)
exit nonzero iff any mismatch or error
```

- **Verdict contract:** exit 0=accept, 1=reject, 2=skip(unmodeled construct, loud),
  3=internal error(FAIL). Never let "skip" masquerade as agreement — count it.
- **CI job (in `march-lean`):** `lake exe cache get` (prebuilt Mathlib) →
  `lake build march-lean-check` → fetch pinned `march` binary + corpus →
  run harness. Cache the Mathlib toolchain aggressively (the dominant cost).
- **Publish** `march-lean-check` as a release artifact on tag, so a later
  non-blocking `march`-repo mirror job can consume it without Mathlib.
- **Getting `march`:** either build it from the pinned March SHA in the
  `march-lean` CI (needs the OCaml/opam toolchain — moderate) or, cleaner,
  consume a published `march` release binary. Prefer a published binary once
  March starts releasing them; until then, build from the pinned SHA.

---

## 6. Risks / open questions for the agent

- **Inference parity (A2) is the hard part.** March's HM inference has
  provenance tracking, row-polymorphism-ish record handling, interface-constraint
  discharge, and the linearity interaction. Getting Lean's inference to agree on
  the *reject* side (especially *why* something is rejected) is where effort
  concentrates. Scope A2 to the fragment the corpus actually exercises; grow the
  corpus and the Lean fragment together.
- **Elaboration-sharing caveat (A1).** A1 checks March's *own* elaboration, so a
  self-consistent-but-wrong inference could still check. A1's differential signal
  is real but weaker than A2's; don't oversell A1 as full conformance.
- **JSON format churn.** Freeze with `format_version`; bump deliberately. The
  march-side golden guards it.
- **Corpus growth is the flywheel.** Every new type-system feature or bug fix in
  March should add an accept/reject witness (already the house style). The
  conformance gate then automatically demands the Lean model keep up — which is
  the whole point: it converts "keep the model in sync" from a discipline into a
  red CI.

---

## 7. Why this is the right first move (for the reviewer)

- **Decoupled from the 35–56-week proof effort.** A2 is a *guardrail today*; the
  proofs are a *theorem later*. Same Lean code, upgraded.
- **A second type-checker is a strong bug-finder** independent of any proof —
  the differential-oracle logic that already caught real bugs in this repo,
  applied to the type system instead of the runtime.
- **It forces the type rules into crisp judgment form**, which is the stated
  pre-proof value in `lean4-metatheory-plan.md` — you get that as a side effect.
- **It keeps Mathlib out of March's build** while still giving March CI an
  optional signal.

Stage B (prove `TypeRules` sound/complete → progress+preservation, linear safety)
and Stage C (mechanize Perceus RC — the novel, publishable result) build ON this
executable checker. Do not start B/C until A2 is green over the corpus.
