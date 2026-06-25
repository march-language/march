# Refinement-Verified Actor State Migration for Hot Code Reload

**Date:** 2026-06-25
**Status:** In progress — §7 step 1 (Gap #1 spike) done; steps 2–5 pending
**Depends on:** HCR Phase 5 (actor state migration; `_migrate_state` recognition in TIR + `__migrate_<Actor>` export); refinement checking A0–A2 (`lib/refine/`, `lib/refinecheck/`); refinement postconditions (`refine_check.ml:834`)
**Spec parents:** `specs/plans/2026-06-24-hcr-phase5-design.md`, `specs/2026-06-21-refinement-types-state-and-forward-design.md`

---

## Motivation

Phase 5 makes hot deploys *operationally* correct for stateful actors: a `migrate_state` function runs before any new-version handler touches old-typed state, and a `Schema_diff` over `.schemas.json` blocks structurally-incompatible deploys. But Phase 5 proves **nothing about what `migrate_state` computes**. A migration that drops a field, miscomputes a counter, or violates the new version's state invariant compiles, deploys, and silently corrupts every live actor. The schema diff is purely structural — it sees that `count : Int` survives and `history : List(Int)` was added; it cannot see that the new code requires `len(history) == count` and the migration sets `history = Nil` while preserving a non-zero `count`.

This spec closes that gap with **static verification**: at deploy time, prove

```
∀ old. inv_old(old)  ⟹  inv_new(migrate_state(old))
```

where `inv_old` is the OLD version's state invariant and `inv_new` is the NEW version's. If the new code maintains an invariant `I` on `State` (every handler preserves it), then a migration is *sound* exactly when it carries every state satisfying `inv_old` to a state satisfying `inv_new`. A migration that cannot be proven sound is rejected before ACTIVATE is sent.

### The key insight: migration soundness *is* a pre/postcondition VC

The obligation above is structurally identical to a precondition/postcondition verification condition on the single function `migrate_state`:

- give `migrate_state` the **refined parameter type** `{ old : RawRecord | inv_old(old) }` (precondition = the old invariant), and
- give it the **refined return type** `{ v : State | inv_new(v) }` (postcondition = the new invariant).

Then "migration is sound" is exactly "`migrate_state`'s return value satisfies its postcondition under its precondition" — which is *precisely* what `refine_check.ml`'s existing postcondition pass (`check_fn_post` → `tails` → `check_post`, lines 834–926) already checks for refined-return functions. The VC it builds is `assumptions = [inv_old(old)] ; goal = inv_new(return)`, discharged via `Refine.discharge` and the BLAKE3 VC cache. **Most of this feature is wiring existing pieces together, not new infrastructure.** The new work is three contained gaps (below), the first of which (record/state-level refinements) is independently useful as actor invariants enforced by every handler.

---

## Verification of the current code (what is actually on `main`)

Every claim below was confirmed by reading the named file/line. Corrections to the working summary are flagged **[CORRECTION]**.

### A. Refinement engine — confirmed
- `lib/refine/`: `smt.ml` (72 lines) — `Smt.term` AST + SMT-LIB2 renderer over the **Int/Bool linear-arithmetic + EUF** fragment; sorts are `SInt | SBool | SData of string` (datatype sorts already exist). `solver.ml` (96) — long-lived `z3 -in` driver, one process per compilation, `push`/`pop` per VC, 3 s per-query timeout. `vc_cache.ml` (62) — BLAKE3-keyed verdict cache at **`<root>/.march/cas/vc/<prefix2>/<rest>`** (`vc_cache.ml:35`, `key_of_vc` = BLAKE3 of `preamble ^ "\n" ^ assertion_block`). `refine.ml` (38) — `Refine.discharge ~root ?preamble vc : outcome` (`Verified | Refuted model | Unverified`), cache→solver→cache.
- `lib/refinecheck/refine_check.ml` (1069 lines) — post-typecheck AST pass. Supports `{Int | p}` params (preconditions), the `len` measure + user `@[measure]` axiomatisation (datatype recursion-equation axioms, M-a/M-b/M-c), path sensitivity, and postconditions. **Soundness stance: definite-failure discharge** — report only when the predicate can *never* hold (`refine_check.ml:814–832`); anything unreflectable is conservatively SKIPPED. No false positives.

### B. Postcondition mechanism — confirmed, and it is the reuse target
- `return_refine` (`refine_check.ml:838`) extracts `(binder, pred)` from a refined return type. `tails` (`:845`) walks return positions through `EBlock`/`EIf`/`ECond`/`EMatch`, accumulating the path condition reaching each. `scope_facts` (`:859`) turns each refined parameter into an SMT assumption true throughout the body. `check_post` (`:870`) reflects the tail expression, assumes `scope_facts ∪ path`, and discharges `goal = ret_pred[binder := tail]`. This is *exactly* `inv_old ⊢ inv_new(return)` once the param/return refinements range over a record.

### C. The blocking gate — confirmed (gap #1)
- `is_int_base` (`refine_check.ml:32`) returns true only for `TyCon("Int", [])`. It gates **both** sites that admit a refinement: `refined_int_ty` for params (`:552–554`) and `return_refine` for returns (`:838–842`). **Refinements cannot currently range over a record/state value** — `{ s : State | … }` is parsed (`TyRefine`, see E/parser below) but dropped by both gates. This is gap #1.

### D. **CRITICAL UNKNOWN — field projection in SMT — ANSWER: NOT present (greenfield for fields; sorts are incremental).**
- The predicate→SMT translator `smt_of` (`refine_check.ml:487–517`) handles literals, variables (`resolve_var`), measure applications `m(x)` where the argument is a **bare variable** (`:495`), and the arithmetic/comparison/boolean operators. **There is no case for `A.EField`** (`s.field`) anywhere in `smt_of`. `EField` appears only in `children` (`:371`) and the `visit` walker (`:976`), never in term reflection. So `s.count` inside a predicate reflects to `None` and the whole VC is silently skipped today.
- **However, the datatype/field *sort* machinery already exists and is reusable.** `ctor_field_sorts`/`adt_ctors` (`:75–76`), `smt_sort_of_field` (`:94`), `ctor_field_sorts` registration (`:114–127`), the `SData` sort and `App(ctor, …)` constructor reflection (`reflect_dt`/`reflect_field`, `:754–777`), and `datatype_decls` (`:225`) are all present and are how measures already range over ADTs. A March **record** is a single-constructor ADT; SMT-LIB `declare-datatypes` gives every field a selector (already emitted as `<ctor>_<i>` accessor names in `ctor_decl`, `:215–221`). So reflecting `s.count` means: declare `State` as a one-constructor datatype (machinery exists), then translate `A.EField(EVar s, "count")` to the field's SMT selector applied to `s` (machinery does *not* exist — must be added to `smt_of`).
- **Verdict:** the SMT *sorts and datatype declarations* are incremental (reuse existing ADT modelling); the *field-projection term case* in `smt_of` is genuinely new. This makes gap #1 **medium**, not large — see Sizing.

### E. HCR Phase 5 — confirmed with two corrections
- **[CORRECTION] `migrate_state` is NOT recognized in `lib/typecheck/typecheck.ml`.** Searching the whole `lib/` tree, `migrate_state`/`RawRecord` appear only as the **`_migrate_state` naming-suffix convention** in TIR passes: `lib/tir/mono.ml:728`, `lib/tir/dce.ml:108`, and `lib/tir/llvm_emit.ml:5812`. The Phase 5 design's "typechecker recognizes `migrate_state(old : RawRecord)` + CAS elaboration of `RawRecord`" (Approach 1) was **not implemented as written** — there is no `RawRecord` type, no typecheck-time prior-CAS elaboration, no return-type disambiguation in the typechecker. The shipped mechanism is the structural suffix + per-actor `__migrate_<Actor>` export. The new feature must therefore introduce the *typed* view of `migrate_state` itself (it cannot assume one exists).
- **`__migrate_<Actor>` alias export — confirmed** at `llvm_emit.ml:5812–5856`: any TIR fn whose name ends `_migrate_state` gets an LLVM alias `@__migrate_<Actor>` (ptr→ptr), actor name recovered from the name before the suffix, last dotted component, first letter capitalised. `march_reload.c` dlsyms the same name.
- **Phase-5 guardrail is PURELY STRUCTURAL — confirmed.** `forge/lib/schema_diff.ml` diffs field name/type only (`diff_actor`, `:87`), `check_compat` (`:105`) is a name/type policy check, `requires_migration` (`:145`) is `changes <> []`. **Nothing inspects `migrate_state`'s computed value.** This is exactly the gap the new feature fills.

### F. Schema persistence — confirmed with one correction
- `.schemas.json` stores **only `{name, ty}` per field** — confirmed: emitted by `bin/main.ml:1823–1845` (`{"name":…,"ty":…}`), parsed by `schema_diff.ml:8` (`type field = { name; ty }`). No predicate field. This is gap #2.
- Emitted only when **both `--hot-reload` and `--compile-so`** are active (`bin/main.ml:1228–1241`, gated on `!hot_reload_prefix` and `!compile_so`), sourced from TIR `TDRecord` types named `*_State` (`lower.ml:1732`); `@compat` policy comes from `DActor.actor_compat` (AST `actor_compat`, `bin/main.ml:1214–1227`).
- **[CORRECTION] `forge deploy hot` does NOT fetch the prior schema from the CAS by `impl_hash`.** `cmd_deploy_hot.ml` reads the prior schema from a **local sidecar file** `<.march>/<project>_hot.so.schemas.json.prev` (`cmd_deploy_hot.ml:502–504`), written after each successful deploy (`:517–529`), and diffs it against the fresh `<so>.schemas.json` (`:500–514`, `run ~old_schemas_path ~new_schemas_path`). The deploy-time diff machinery (`Schema_diff.diff_schemas`, `check_compat`, `migrate_required`) lives **in forge**, not the compiler (`:336–382`). This affects gap #2/#3: the "old predicate" travels in the same local `.prev` sidecar, and the VC, like the existing diff, naturally belongs in forge's deploy path.

---

## Decisions

| Question | Answer |
|---|---|
| Reframing | Migration soundness VC = pre/postcondition VC on `migrate_state`: param `{RawRecord | inv_old}`, return `{State | inv_new}`. Reuse `check_post`. |
| Invariant surface syntax | **`@invariant(pred)` attribute on the actor `State` type** (recommended over a `{v : State | …}` refined type alias). Rationale below. |
| Field projection in SMT | Model each actor `State` record as a one-constructor SMT datatype (reuse `ctor_field_sorts`/`datatype_decls`); add an `A.EField` case to `smt_of` that emits the field selector. |
| `inv_old` provenance | Serialize the invariant predicate string into `.schemas.json` (new optional `"invariant"` key per actor); it rides the existing `.prev` sidecar to deploy. |
| Where the migration VC runs | **A new compiler `--check-migration` mode**, shelled out to by `forge deploy hot` (not reimplemented in forge). Rationale below. |
| Soundness stance | Inherit definite-failure discharge: a migration is *rejected* only when `inv_new(migrate(old))` can be proven to fail under `inv_old(old)`; an unreflectable predicate is conservatively *accepted* (no false-reject). Same no-false-positive contract as `refine_check`. |
| First deploy / no prior invariant | No `inv_old` ⟹ assume `true` (vacuous precondition) ⟹ VC degenerates to "every reachable `migrate_state` return satisfies `inv_new`", which is still useful and never spuriously rejects. |

### Why `@invariant` on the State type, not a refined type alias

A refined alias (`type State = { v : RawState | v.count >= 0 }`) would require refinements to range over *type definitions*, entangling gap #1 with the type-alias/nominal-type machinery and forcing every `State` mention to carry the predicate. An **attribute** `@invariant(count >= 0 && len(history) == count)` attached to the `DType`/`DActor` is:
- precedent-aligned: `@compat(...)` is already an actor-State attribute parsed to `actor_compat` (`ast.ml:277`), and `@[measure]` is already a function attribute (`fn_attrs`, `ast.ml:227`) consumed by `refine_check`. `@invariant` is the same shape.
- decoupled: the predicate is one string on one declaration; handlers and `init` keep their plain `State` types. The refine pass *synthesises* the refined param/return for `migrate_state` from the attribute — it does not need refined record types to exist in the surface language for ordinary code.
- serializable: one attribute string drops straight into `.schemas.json` (gap #2).

The independently-useful corollary (checking that *every handler* preserves `@invariant`) is a natural extension (§6) but is not required for the migration VC.

---

## 1. The reframing, concretely

For an actor `Counter` with new-version `@invariant(I_new)` and a prior deployed `@invariant(I_old)`, the compiler synthesises, purely internally, the refined signature of the migration function:

```
migrate_state : { old : RawRecord | I_old(old) }  →  { v : State | I_new(v) }
```

`RawRecord` is the prior `State` shape (its field names/types come from the prior `.schemas.json`; see §3). The refine pass then runs its **existing** `check_fn_post` machinery on this one function:

- `scope_facts` contributes the assumption `I_old(old)` (today: only for Int params — gap #1 lifts this to a record param).
- `tails` walks every return position of `migrate_state` under its path conditions.
- `check_post` discharges `goal = I_new(return)` against `assumptions = I_old(old) ∪ path`, through `Refine.discharge` and the VC cache.

No new VC builder, solver wiring, cache, or counterexample formatter is needed — `format_cx` (`refine_check.ml:535`) already renders the rejecting model. The only genuinely new reasoning is reflecting `old.field` / `return.field` into SMT (gap #1).

---

## 2. Gap #1 — record/state-level refinements (field projection)

**What:** lift `is_int_base` so `{ s : State | p }` is admitted as a param/return refinement, and teach `smt_of` to reflect `s.field`.

**How:**
1. Generalise the gate. Replace the two `when is_int_base base` guards (`refine_check.ml:553`, `:840`) with a predicate that also admits a `TyCon(record_name, _)` whose record type is registered as a single-constructor datatype. Record the *base sort* on the scope entry (`SInt` today; now possibly `SData "M_State"`).
2. Register record types as datatypes. Records reach `refine_check` as the actor `State` ADT/record; extend `register_adt_names`/`register_field_sorts` (`:103–127`) — already two-pass — to also register `DType(_, name, _, TDRecord fields, _)` as a one-constructor datatype `M_<name>` whose single constructor has the record's fields as selectors. `smt_sort_of_field` (`:94`) already maps field types to `SInt`/`SBool`/`SData`/`Elem`.
3. **Add the `EField` case to `smt_of`** (the new term reflection). When reflecting `A.EField(EVar s, f)` and `s` is a record-sorted scope binder, emit the SMT selector for field `f` of `s`'s datatype — i.e. `App("<ctor>_<idx_of_f>", [Const s])`, reusing the accessor naming already produced by `ctor_decl` (`:215`). The field index/sort comes from `ctor_field_sorts`. `len(s.history)` then composes naturally: the existing measure case (`:495`) currently requires a bare-variable argument; extend it to accept a reflected field projection (a one-line broadening of the `[a]` argument match to "any reflectable term whose sort is a list datatype").
4. Reflect the **returned record literal**. A `migrate_state` body returning `{ count = old.count, history = Nil }` is an `A.ERecord`; reflect it as the datatype constructor application `App("<ctor>", [reflect(field_exprs)…])` (the constructor-reflection path `reflect_dt`, `:755`, already does this for `ECon`; add the `ERecord` shape). Then `return.count` in `I_new` selects field 0 of that constructor application and the recursion-equation/selector axioms fire.

**Soundness:** unchanged stance — any field whose value is a non-record/non-list expression we cannot reflect makes the VC skip (accept). `Elem`-sorted fields (opaque element types) reflect to fresh constants exactly as measures already treat them.

**Independently useful:** with this in place, `@invariant` on `State` can also be checked against `init()` and every handler's return (each is a refined-return obligation in the same `check_fn_post` shape) — see §6.

---

## 3. Gap #2 — persist the old predicate across versions

**What:** make `inv_old` available at the deploy boundary.

**How:** extend `.schemas.json` with one optional per-actor key, `"invariant"`, carrying the predicate's source text.

```json
{
  "Counter": {
    "compat": "full",
    "invariant": "count >= 0 && len(history) == count",
    "state_fields": [
      { "name": "count",   "ty": "Int" },
      { "name": "history", "ty": "List(Int)" }
    ]
  }
}
```

- **Emit** (`bin/main.ml:1823–1845`): read the actor's `@invariant` attribute (new `actor_invariant` field on `DActor`, sibling to `actor_compat`) and write the `"invariant"` line. Absent attribute ⟹ omit the key (treated as `true`).
- **Parse** (`schema_diff.ml:28`): add an `invariant : string option` field to `actor_schema` and a line-detector mirroring the existing `"compat":` one (`:59`).
- **Provenance:** unchanged plumbing — the prior schema (now including `inv_old`) already rides the local `.prev` sidecar (`cmd_deploy_hot.ml:502`). **[CORRECTION vs. summary]** there is no CAS-by-`impl_hash` fetch to extend; the predicate travels in the file that already travels.

**Sizing note:** the existing `.schemas.json` parser is a hand-rolled line scanner (`schema_diff.ml:39–78`). Adding one key is small and matches the existing `"compat"` handling exactly; no JSON library is introduced.

---

## 4. Gap #3 — run the migration VC at the deploy boundary

**The cross-version problem:** `refine_check` runs in-compiler over *one* program. The migration VC needs `inv_old` (from the prior `.schemas.json`, a *different* version) and `inv_new` + the `migrate_state` body (from current source). The current build does not know `inv_old`.

**Decision: a new compiler `--check-migration` mode, invoked by `forge deploy hot`.** Rather than reimplement SMT reasoning in forge, `forge deploy hot` shells out to the compiler:

```
march --check-migration \
      --prior-schema <project>_hot.so.schemas.json.prev \
      --new-schema   <so>.schemas.json \
      <entry>.march
```

The mode: (a) parses/typechecks current source as usual; (b) for each actor with both a `migrate_state` and a prior `"invariant"` in `--prior-schema`, synthesises the refined signature of §1 — param `{RawRecord | inv_old}` (parsing `inv_old`'s string against the prior fields), return `{State | inv_new}` (the current `@invariant`); (c) runs `check_fn_post` on just that function; (d) exits non-zero with the existing refinement-violation diagnostic (incl. `format_cx` counterexample) if the VC is refuted.

`forge deploy hot` runs this between the schema-diff/`check_compat` step and CAS_PUT/ACTIVATE (`cmd_deploy_hot.ml:336–356`): a non-zero exit aborts the deploy with the compiler's diagnostic, exactly as a `check_compat` violation already aborts (`:351–358`).

**Tradeoff (why not move the check into forge):** forge would need to link `lib/refine` + `lib/refinecheck` + parse predicates + reconstruct the prior record type — i.e. half the front end. The compiler already has all of it, plus the parser for the predicate strings, plus the VC cache rooted at the project. Shelling out keeps one SMT reasoner, one cache, one diagnostic format, and lets the predicate parser stay where the lexer/parser live. The cost is one extra `march` invocation per deploy (cached VCs make repeats instant). This mirrors how forge already shells out to the compiler for builds rather than embedding it.

---

## 5. Sizing & risk (honest, per gap)

| Gap | Size | Evidence |
|---|---|---|
| **#1 record/state refinements** | **Medium** | Sorts/datatype declarations are *incremental* (reuse `ctor_field_sorts`, `smt_sort_of_field`, `datatype_decls`, `reflect_dt` — all present, `:75–127`, `:225`, `:755`). The genuinely new code is: (a) lift two `is_int_base` gates, (b) register `TDRecord` as a 1-ctor datatype, (c) **add the `A.EField` selector case to `smt_of`** (absent today — finding D), (d) reflect `ERecord` return literals as constructor apps. All four are localized to `refine_check.ml`. No solver/cache/typechecker change. Risk: `Elem`-typed fields and nested records reflect to fresh constants (sound, but the VC may skip rather than prove — acceptable under the no-false-positive contract). |
| **#2 persist old predicate** | **Small** | One optional key added to a hand-rolled emitter (`bin/main.ml:1837`) and line-scanner parser (`schema_diff.ml:59`), plus one `actor_invariant` AST field paralleling `actor_compat`. No new file formats, no CAS changes (predicate rides the existing `.prev` sidecar — finding F correction). |
| **#3 deploy-boundary VC** | **Medium** | New `--check-migration` CLI mode in `bin/main.ml` (parse two schema paths, synthesise the refined sig, call the *existing* `check_fn_post`), plus ~15 lines in `cmd_deploy_hot.ml` to shell out and gate on exit code (the abort path already exists, `:351–358`). The reasoning core is reused verbatim. Risk: parsing `inv_old` against a reconstructed prior record type — but the prior field set is exactly what `.schemas.json` already carries, so the reconstruction is mechanical. |

**Cross-cutting risk:** the whole feature is *advisory-to-blocking* only at deploy; it never changes a compiled artifact, so it is **not** part of the CAS cache key (same stance as `measure_axioms`, `refine_check.ml:1025–1031`). If `z3` is absent, `Refine.discharge` returns `Unverified` ⟹ the VC skips ⟹ deploy proceeds (graceful degradation, matching every other refinement check).

---

## 6. Optional extension — invariants checked per handler (independently useful)

Once gap #1 lands, `@invariant(I)` on `State` can be enforced on *ordinary* code with zero migration involvement: `init()` and every handler return `State`, so each is a refined-return obligation `check_fn_post` already handles. This catches an `Inc` handler that forgets to push onto `history` (`len(history) != count`) at *compile* time, not deploy time, and makes `inv_old` actually *true* of every old state (strengthening the migration precondition rather than assuming it). Recommended as a fast-follow but not on the critical path for migration verification.

---

## 7. Phased implementation plan (vertical slice first)

1. ✅ **Spike (gap #1 core, finding D) — DONE (2026-06-25, commit `e1f02166`):** `A.EField` selector case added to `smt_of` (via optional `~resolve_field` hook); `TDRecord` registered as 1-ctor SMT datatype with `ctor_field_names` hashtable; `type_preamble`/`record_vc_preamble()` dedup with `measure_preamble`; `reflect_record_literal` reflects `ERecord` return values; `check_post` extended with `?record_sort`. Verified: `{ s : State | s.count >= 0 }` discharges on `{ count: 1 }` and rejects `{ count: -1 }` (3 new tests in `record-postconditions` group, 54 total in `test/test_refinecheck.ml`). Plan: `specs/plans/2026-06-25-refine-check-record-spike.md`.
2. **Gap #1 full:** lift both `is_int_base` gates; reflect `ERecord` return literals; broaden the `len` measure to accept field-projection arguments. Land with refinecheck unit tests over a record param/return.
3. **Gap #2:** `actor_invariant` AST field + emit/parse the `"invariant"` key. Round-trip test through `.schemas.json`.
4. **Gap #3:** `--check-migration` CLI mode reusing `check_fn_post`; then the `cmd_deploy_hot.ml` shell-out + exit-code gate.
5. **End-to-end:** the Counter v1→v2 example below, proven and rejected (§9), on the droplet harness already used for Phase 5.

---

## 8. What to spike first

**Field-projection reflection in `smt_of` (gap #1, finding D).** Everything else assumes `s.count` and `return.count` become SMT terms. Concretely, the spike must show that:

```march
@invariant(count >= 0)
type State = { count : Int }
fn migrate_state(old : RawRecord) : State do { count = old.count } end
```

with prior `@invariant(count >= 0)` produces an SMT VC of the shape

```
(declare-datatypes ((M_State 0)) (((State (State_0 Int)))))
(declare-const old M_State)
(declare-const ret M_State)
(assert (>= (State_0 old) 0))          ; inv_old(old)
(assert (= ret (State State_0_of_old))); ret = migrate(old) = { count = old.count }
(assert (not (>= (State_0 ret) 0)))    ; ¬inv_new(ret)
(check-sat)                            ; expect unsat ⟹ Verified
```

If the selector term (`State_0`) and the constructor-application reflection of the `ERecord` return both fall out of the existing `ctor_decl`/`reflect_dt` naming, gap #1 is medium and the rest is plumbing. If they don't compose (e.g. selector names clash, or `ERecord` can't reach `reflect_dt`), gap #1 grows — settle this first.

---

## 9. End-to-end example

### v1 (deployed)

```march
mod MyApp.Counter do
  @invariant(count >= 0)
  type State = { count : Int }

  fn init() : State do { count = 0 } end
  fn handle(state : State, msg : Msg) : State do
    match msg do
      Inc -> { count = state.count + 1 }
      Get -> state
    end
  end
end
```

`.schemas.json` (v1): `"Counter": { "compat": "full", "invariant": "count >= 0", "state_fields": [{"name":"count","ty":"Int"}] }`.

### v2 — sound migration (VC proves it; deploy proceeds)

```march
mod MyApp.Counter do
  @invariant(count >= 0 && len(history) == count)
  type State = { count : Int, history : List(Int) }

  fn migrate_state(old : RawRecord) : State do
    -- prior State = { count : Int }; inv_old = (count >= 0)
    { count = old.count, history = list_repeat(0, old.count) }
  end

  fn init() : State do { count = 0, history = Nil } end
  fn handle(state : State, msg : Msg) : State do
    match msg do
      Inc -> { count = state.count + 1, history = state.count :: state.history }
      Get -> state
    end
  end
end
```

VC: `assume count_old >= 0`; `ret = { count = count_old, history = repeat(0, count_old) }`; goal `ret.count >= 0 && len(ret.history) == ret.count`. With `len(repeat(0, n)) == n` available (from the `repeat` measure axiom) and `ret.count == count_old >= 0`, the goal holds ⟹ **Verified** ⟹ deploy proceeds.

### v2′ — UNSOUND migration (VC rejects it; deploy aborts)

```march
  fn migrate_state(old : RawRecord) : State do
    { count = old.count, history = Nil }   -- WRONG: drops the history invariant
  end
```

VC: `assume count_old >= 0`; `ret = { count = count_old, history = Nil }`; goal `count_old >= 0 && len(Nil) == count_old`, i.e. `0 == count_old`. Negation `count_old != 0` is satisfiable under `count_old >= 0` (e.g. `count_old = 1`) ⟹ **Refuted**. `forge deploy hot` aborts before ACTIVATE:

```
error: refinement violation: return value cannot satisfy postcondition
       `count >= 0 && len(history) == count` (counterexample: count = 1)
note: every return path of migrate_state must satisfy `count >= 0 && len(history) == count`
deploy aborted: migrate_state for Counter is not provably sound
```

---

## Files Changed

| File | Change |
|------|--------|
| `lib/refinecheck/refine_check.ml` | Lift `is_int_base` gates (`:553`, `:840`) to admit record-typed refinements; register `TDRecord` as a 1-ctor datatype in `register_adt_names`/`register_field_sorts` (`:103–127`); **add `A.EField` selector case to `smt_of`** (`:487`); reflect `A.ERecord` return literals as constructor apps in `reflect_dt` (`:755`); broaden the `len`/measure argument from bare-var to any reflectable field projection (`:495`). |
| `lib/ast/ast.ml` | New `actor_invariant : string option` (sibling to `actor_compat`, `:277`); `@invariant` accepted as a `DType`/`DActor` attribute. |
| `lib/parser/parser.mly` | Parse `@invariant(pred)` on the actor `State` type (mirrors `@compat`). |
| `bin/main.ml` | Emit the `"invariant"` key in `.schemas.json` (`:1837`); new `--check-migration --prior-schema --new-schema` CLI mode that synthesises the refined `migrate_state` signature and runs `check_fn_post`. |
| `forge/lib/schema_diff.ml` | `invariant : string option` on `actor_schema`; parse the new key (mirror `"compat":` scanner, `:59`). |
| `forge/lib/cmd_deploy_hot.ml` | Shell out to `march --check-migration` between `check_compat` and ACTIVATE; abort on non-zero exit (reuse the existing abort path, `:351–358`). |
| `test/test_refinecheck.ml` | Record param/return refinement cases; `migrate_state` sound/unsound pair. |
| `forge/test/test_forge.ml` | `.schemas.json` `"invariant"` round-trip. |

---

## Failure Modes

| Situation | Behavior |
|-----------|----------|
| `migrate_state` proven unsound (VC refuted) | `forge deploy hot` aborts before ACTIVATE; prints the refinement diagnostic + counterexample. |
| `inv_new` references an unreflectable field/expr | VC skips (accept) — definite-failure stance; no false reject. Same as `refine_check` today. |
| No prior `"invariant"` in `.prev` (first deploy / pre-feature build) | `inv_old = true`; VC reduces to "every return satisfies `inv_new`"; never spuriously rejects. |
| `z3` unavailable | `Refine.discharge` → `Unverified` → VC skips → deploy proceeds (graceful, like all refinement checks). |
| Actor has `@invariant` but no `migrate_state`, state type changed | Existing Phase 5 path (supervisor restart from `init()`); the new VC has nothing to check. The §6 extension would instead verify `init()` satisfies `inv_new`. |
| `@invariant` predicate fails to parse | Compile error at the version that *introduced* it (ordinary parse error), before it can reach a schema file. |

---

## Cross-references (confirmed paths/lines)

- Postcondition reuse target: `lib/refinecheck/refine_check.ml:834–926` (`return_refine`, `tails`, `scope_facts`, `check_post`, `check_fn_post`).
- Blocking gate: `refine_check.ml:32` (`is_int_base`), `:553` (param), `:840` (return).
- Field-projection absence: `smt_of` `refine_check.ml:487–517` (no `EField` case); datatype machinery `:75–127`, `:225`, `:755`.
- VC cache: `lib/refine/vc_cache.ml:35` (`.march/cas/vc/`), `refine.ml:22` (`discharge`).
- Phase 5 `__migrate_<Actor>` export: `lib/tir/llvm_emit.ml:5812–5856`; suffix recognition `lib/tir/mono.ml:728`, `lib/tir/dce.ml:108`.
- Structural-only guardrail: `forge/lib/schema_diff.ml:87` (`diff_actor`), `:105` (`check_compat`).
- Schema emit: `bin/main.ml:1823–1845`; parse: `schema_diff.ml:28–84`.
- Prior-schema source (local sidecar, not CAS): `cmd_deploy_hot.ml:502–514`, deploy abort path `:351–358`.
- Refined-type parser productions: `lib/parser/parser.mly:878–884`.
