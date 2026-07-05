# Core March Static Semantics (typing) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Widen the typing walking skeleton (`specs/lang/core-march-types.md`) to a
complete **Core March Static Semantics reference** for the same core fragment the
operational semantics (`core-march.md`) covers — ADT constructors + `match`,
tuples, records, atoms, the full pattern language + guards, local recursive
functions, conditionals, and the interface-constraint model that discharges the
`Num`/`Eq`/… constraints — each rule transcribed arm-for-arm from
`lib/typecheck/typecheck.ml` and anchored by the `accept/reject` conformance
corpus. Together with `core-march.md`, this completes **Level-1 for the core**
(operational + typing).

**Architecture:** Replicate the proven typing-skeleton template — **judgment →
cited typing rules → `accept/`+`reject/` conformance programs** — for each
construct group, growing `core-march-types.md` and `specs/lang/types/`. Each
`reject/` program pins the compiler's EXACT diagnostic (captured from `march
--check`, never guessed) as an `-- EXPECT-ERROR:` annotation, so `check_types.sh`
catches both a spec-vs-typechecker mismatch and a diagnostic regression. Late
tasks wire `check_types.sh` into a CI lane and consolidate into "reference v1".

**Tech Stack:** Markdown spec + `.march` accept/reject programs + `march --check`
(exit 0 = accept; exit 1 + `-- ERROR --` + message = reject) driven by
`specs/lang/types/check_types.sh`; `lib/typecheck/typecheck.ml` as the source of
truth (bidirectional HM: `infer_expr` :3236 ⇒, `check_expr` :4164 ⇐,
`generalize` :845, `instantiate` :897, `infer_pattern` :2566, `instantiate_ctor`
:2387, `infer_match` :4273, `infer_block` :4293).

## Global Constraints

- **Base:** `origin/main` at plan time (contains the typing skeleton commit
  `6293b017`). Worktree ONLY:
  `/Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3`, branch
  `docs/core-march-types-skeleton` (accumulate here; controller merges at the end).
- **The template is `specs/lang/core-march-types.md`.** Every task produces the
  same shape (judgment excerpt if new, cited typing rules in §2-style, an
  `accept/reject` table row per program) in that exact style. Read it first; do
  not invent a new format. Cross-reference `core-march.md` for the operational
  counterpart of each construct.
- **Faithfulness is the whole point.** Every typing rule MUST cite the
  `typecheck.ml` line(s) it is transcribed from. Rules are human-reviewed; the
  `accept/reject` corpus is the mechanical anchor. A rule with no citation is a
  defect.
- **`check_types.sh` must stay GREEN at every commit.** Run it
  (`MARCH_BIN=$PWD/_build/default/bin/main.exe specs/lang/types/check_types.sh`,
  ~seconds). Every `accept/*.march` must typecheck (exit 0); every `reject/*.march`
  must be rejected (exit 1) AND its `--check` output must contain its
  `-- EXPECT-ERROR:` substring.
- **REJECT error substrings are captured, not guessed.** For every `reject/`
  program, run `march --check` yourself, read the ACTUAL diagnostic, and pin a
  stable, distinctive substring of it as the `-- EXPECT-ERROR:` first line. If the
  message is long/positional, pin the invariant phrase (e.g. `` expects 1 argument ``),
  not the file path or line numbers.
- **Type-side flywheel (bugs are wins, but never redden the corpus):** if you
  find a program the spec says should typecheck but the typechecker REJECTS (or
  vice versa), or a program that CRASHES the typechecker (uncaught exception /
  internal error rather than a clean exit-1 diagnostic), that is a real bug —
  reproduce it by hand, file it in `specs/todos.md` with a minimal repro, and
  either leave it OUT of the corpus or record it in a "known typing divergence"
  note in `core-march-types.md`. Never commit a program that reddens
  `check_types.sh`, and never paper over a divergence by weakening a rule.
- **Deferred — NOT this plan** (later slices / roadmap Phase 2b–3): refinement
  types (the z3-discharged `{v:T | p}`), linearity/affinity, capabilities,
  effects, session types, and the FULL user-defined interface/impl coherence
  machinery (Task 6 documents the *constraint model* for the built-in
  `Num`/`Eq`/`Ord`/`Show` interfaces only — a complete trait-system formalization
  is out of scope).
- **Process:** foreground only; `check_types.sh` is the gate (isolated HOME not
  needed — `--check` does no codegen, so no CAS/`~/.cache` involvement). This is
  a docs-only plan; NO task should modify `lib/`/`bin/` (if a task feels like it
  needs to change `typecheck.ml`, that means it found a bug — STOP, file it, do
  not fix it here). No `git stash`; explicit staging by name; no Co-Authored-By;
  never pipe `march --check` output to a wedging pager (redirect to files).

---

### Task 1: ADT constructors + `match` typing

**Files:** Modify `specs/lang/core-march-types.md`; Create `specs/lang/types/accept/t0N_*`, `reject/t0N_*`.

**Constructs:** a `type` declaration's constructors as typed values; `ECon C [args]`
typing (constructor instantiation); `match` typing — scrutinee, each branch
pattern typed against the scrutinee type, all branch bodies unified to one result
type.

**Extraction (cite `typecheck.ml`):** `instantiate_ctor` (:2387 — how `Some`,
`Cons`, a user 2-ctor ADT get their `arg_tys → result_ty`, with the ADT's type
params instantiated to fresh vars); the `ECon` arm of `infer_expr` (grep `ECon`);
`infer_match` (:4273 — scrutinee type, branch typing, result unification);
`infer_pattern` (:2566) for `PatCon` (checks the constructor exists, its arity,
recurses on sub-patterns, binds pattern vars at the instantiated arg types).

**Deliverable:** typing rules **(T-Con)**, **(T-Match)** (+ the pattern-typing
relation `Γ ⊢ p : τ ⊣ Γ'` for `PatCon`/`PatVar`/`PatWild`/`PatLit`), each cited.
≥3 `accept/` (a 2-ctor ADT constructed + matched; a payload-carrying ctor bound in
a branch; a generic `Option`-like used at two element types) and ≥2 `reject/`
(constructor arity mismatch — pin the actual `Constructor \`C\` expects N argument(s)`
text; a `match` whose branch bodies have different types — pin its message).
`check_types.sh` green. Commit `docs(spec): Core March typing — ADT constructors + match`.

---

### Task 2: Tuples + records typing

**Files:** Modify `specs/lang/core-march-types.md`; Create accept/reject programs.

**Constructs:** `ETuple`/`PatTuple` (`(τ₁,…,τₙ)`); `ERecord` (`{l:τ,…}`), `EField`
(projection), `ERecordUpdate` (`{ base with f: v }`), `PatRecord`.

**Extraction (cite):** the `ETuple`/`ERecord`/`EField`/`ERecordUpdate` arms of
`infer_expr` (grep each); `infer_pattern` for `PatTuple`/`PatRecord`. For
`ERecordUpdate`, pin whether the typechecker checks the updated field EXISTS on
the base's static type (it does for a concrete `TRecord` — this is the static
counterpart of the operational missing-field adjudication in `core-march.md`
§4.2.1; the operational error only fires for an erased/generic base). Note the
record-field surface syntax is `:` not `=` (a fidelity fact the operational spec
already recorded).

**Deliverable:** rules **(T-Tuple)**, **(T-Record)**, **(T-Field)**,
**(T-Update)** + `match(PatTuple/PatRecord)`, cited; note the field-exists check
on `ERecordUpdate` and its relation to the operational adjudication. ≥3 `accept/`
(tuple construct+destructure; record literal + field access; record update on an
existing field), ≥2 `reject/` (field access on a non-record or missing field —
pin the message; record-update on a field absent from a concrete record type —
pin the message). Green. Commit `docs(spec): Core March typing — tuples + records`.

---

### Task 3: Atoms typing

**Files:** Modify `specs/lang/core-march-types.md`; Create accept/reject programs.

**Constructs:** `EAtom` (`:ok`, `:error(x)`), `PatAtom`, the `Atom` type and the
atom-with-payload type.

**Extraction (cite):** the `EAtom` arm of `infer_expr` (grep `EAtom`; also note
the skeleton's finding that `typecheck.ml`'s `EAtom`/`PatAtom` arms DISCARD the
payload's own type — `typecheck.ml:4045–4047` / `:2661–2664` per the atom-print
bug writeup — which is a real, load-bearing typing fact worth pinning); `infer_pattern`
for `PatAtom`.

**Deliverable:** rules **(T-Atom-0)** / **(T-Atom-N)** + `match(PatAtom)`, cited,
including the payload-type-erasure fact. ≥2 `accept/` (nullary atom; payload atom
in a `match`), ≥1 `reject/` if a well-typed rejection exists for atoms (else note
none and say why). Green. Commit `docs(spec): Core March typing — atoms`.

---

### Task 4: Full pattern typing + guards + exhaustiveness

**Files:** Modify `specs/lang/core-march-types.md`; Create accept/reject programs.

**Constructs:** consolidate the pattern-typing relation `Γ ⊢ p : τ ⊣ Γ'` over ALL
core patterns (from Tasks 1–3), plus **guards** (`branch_guard` typed against
`Bool`) and **exhaustiveness** — determine from the code whether `typecheck.ml`
checks match exhaustiveness at type-check time (a warning? an error? nothing —
deferred to runtime `Match_failure`?), and pin the answer with a citation and a
corpus program.

**Extraction (cite):** `infer_pattern` (:2566) fully; where the guard is typed
(grep `branch_guard` in typecheck); the exhaustiveness check site if any (grep
`exhaustiv`/`non-exhaustive`/`unreachable` in `typecheck.ml`).

**Deliverable:** the complete pattern-typing relation, the guard rule, and the
exhaustiveness finding (with its actual behavior), cited. ≥2 `accept/` (a guarded
branch; a nested pattern), ≥1 `reject/` if the typechecker rejects a
type-incorrect pattern (e.g. a `PatLit` int against a `String` scrutinee — pin the
message). If exhaustiveness is a WARNING (not exit-1), note that `check_types.sh`
keys on exit code so a non-exhaustive `accept/` still passes — document it, don't
rely on it as a reject. Green. Commit `docs(spec): Core March typing — patterns + guards + exhaustiveness`.

---

### Task 5: Local recursive functions typing

**Files:** Modify `specs/lang/core-march-types.md`; Create accept/reject programs.

**Constructs:** `ELetFn` (`fn go(params) do … end` in a block) — how the recursive
binding is typed (is `go` in scope monomorphically inside its own body, as in ML
`let rec`? is the return type inferred or must it be annotated?).

**Extraction (cite):** the `ELetFn` arm of `infer_block` (grep `ELetFn` in
typecheck — it typically binds the fn name at a monotype before typing the body so
the recursive call sees it, then generalizes after). Pin whether polymorphic
recursion is rejected (it should be — standard HM).

**Deliverable:** rule **(T-LetFn)**, cited, noting monomorphic-in-body recursion +
whether the result type needs annotation. ≥2 `accept/` (a recursive `fn go`
computing e.g. factorial; a local rec fn used after the block), ≥1 `reject/` if a
polymorphic-recursion or return-type-mismatch case is rejected — pin the message.
Green. Commit `docs(spec): Core March typing — local recursive functions`.

---

### Task 6: Interface-constraint model + conditionals (`ECond`)

**Files:** Modify `specs/lang/core-march-types.md`; Create accept/reject programs.

**Constructs:** (a) the **interface-constraint model** — how the `Num`/`Eq` (and
`Ord`/`Show`) constraints from `+`/`==`/comparisons/`show` (the skeleton's §2.1)
are represented (`CInterface`/`CNum` in schemes, `env.pending_constraints`) and
**discharged** (where/how the solver resolves a constraint against a built-in
`impl`; what happens when no `impl` exists). (b) **`ECond`** (`match do c -> b … end`)
typing — arms' conditions checked against `Bool`, bodies unified (the type-side of
the operational E-Cond rules).

**Extraction (cite):** the constraint types (grep `CInterface`/`CNum`/`pending_constraints`);
the discharge/solve site (grep `solve`/`discharge`/`resolve_constraint`/`CInterface`
handling); the `ECond` arm of `infer_expr`.

**Scope:** document the constraint MODEL for the built-in interfaces
(`Num`/`Eq`/`Ord`/`Show`) — how a constraint arises, is carried on a scheme, and is
discharged — NOT a full user-defined-trait coherence formalization (deferred).

**Deliverable:** an "interface constraints" subsection (constraint syntax on
schemes, the discharge rule, the no-`impl` error) + **(T-Cond)**, cited. ≥2
`accept/` (`1 + 2` and `1.0 +. 2.0` both discharge `Num`; `x == y` on two Ints
discharges `Eq`; an `ECond` chain), ≥2 `reject/` (`1 + "x"` — the two `+` args
can't share one `a`, pin the message; a type with no `Eq`/`Num` impl used with
`==`/`+` if such a reject exists — pin it). Green. Commit `docs(spec): Core March typing — interface constraints + conditionals`.

---

### Task 7: Consolidate into "Static Semantics reference v1" + wire `check_types.sh` into CI

**Files:** Modify `specs/lang/core-march-types.md` (restructure skeleton→reference); Create `specs/lang/types/INDEX.md`; wire the harness into a CI lane.

No new typing rules — assembly + versioning + CI wiring. (a) Re-title/re-status
`core-march-types.md` from "walking skeleton v0" to "Static Semantics reference v1
(core fragment complete)"; unify §2 into one coherent rule set grouped by
construct with every citation preserved (self-check: the count of `(T-…)` labels
and `typecheck.ml:` citations must not DROP); update §5's deferred list to the
roadmap Phase-2b/3 queue; collect any "known typing divergence" notes from Tasks
1–6 into one subsection. (b) Create `specs/lang/types/INDEX.md` mapping each
`accept/reject` program to the rule it anchors. (c) **Wire `check_types.sh` into a
slow CI lane** — mirror how the operational golden corpus is run: add a dune
`(rule (alias types-check) …)` in `test/dune` (or the nearest analog) that runs
the harness, OR add the harness invocation to the existing `@oracle` lane's
script — justify the choice; it must be a *separate slow lane*, not `@runtest`.
Verify the wired lane runs green. Commit `docs(spec): consolidate Core March Static Semantics reference v1 + CI-wire check_types.sh`.

---

### Task 8: Closeout + bookkeeping

**Files:** Modify `specs/progress.md`, `specs/todos.md`, `specs/2026-07-04-language-specification-roadmap-design.md`.

Record: the Static Semantics reference v1 (core fragment complete); the
`accept/reject` corpus count; any typing bugs/divergences found (filed); mark the
roadmap's "type-system track" / Level-1-typing status complete; note that
`core-march.md` (operational) + `core-march-types.md` (typing) together = Level-1
for the core. Final gate: `check_types.sh` green + the wired CI lane green +
doc-lint. Commit `docs: Core March typing Phase complete — Static Semantics reference v1 + closeout`.

---

## Self-review notes

- **Spec coverage:** Tasks 1–6 cover every core construct the typing skeleton
  deferred (ADTs+match, tuples, records, atoms, full patterns+guards+exhaustiveness,
  local-rec-fns, interface constraints, conditionals) — cross-check against the
  operational `core-march.md`'s covered set; the two should reach parity over the
  same fragment. Task 7 consolidates + CI-wires; Task 8 closes out.
- **Sequencing:** ADTs+match first (patterns/constructors underpin everything),
  then the compound types (tuples/records/atoms), then the pattern relation is
  consolidated with guards/exhaustiveness, then local recursion, then the
  interface-constraint model (which the `+`/`==` skeleton rules already forward-
  reference), then consolidate + wire + close.
- **Harness invariant:** every task keeps `check_types.sh` green; the only way to
  "fail" is to discover a real typechecker bug, which is filed (flywheel) not
  papered over. Reject error substrings are captured from the live compiler, never
  guessed — the single most common way this kind of corpus rots.
- **No `lib/` changes:** this is a docs+corpus plan. A task that feels it must edit
  `typecheck.ml` has found a bug; it files it and moves on.
