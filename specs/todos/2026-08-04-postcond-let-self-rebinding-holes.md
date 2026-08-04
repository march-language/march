# A postcondition-derived `let` entry whose predicate mentions the `let`'s own binder (OPEN)

**Shape.** `scope_add_binding`'s `postcond` arm (`lib/refinecheck/refine_check.ml`)
files the callee's return refinement under the `let`'s binder. `postcond_of` has
already substituted the call's **actuals**, so a name in the stored predicate
denotes the value **before** the binding. When the `let` rebinds a name the
predicate mentions, the pre-binding value and the post-binding value collide onto
one SMT symbol, because the fact loaders accept the entry's **own name** as a
spelling of the promised value (`is_self_spelling n = n = b || n = "_" || n = x`
in `load_scope_measure_facts`; the same `n = x` spelling in
`load_scope_tester_facts`). That spelling is correct for a refined **parameter**
entry — there the two really are the same value — and wrong for a
postcondition-derived `let` entry.

The collision does not merely lose precision. It produces a **contradictory
assumption**, and a contradiction discharges every goal, so the VC is vacuously
valid and an impossible obligation is reported **proved**. That is a false proof,
the one outcome this subsystem exists to prevent.

`scope_shadow` already applies exactly the right test (`expr_mentions`) to
**pre-existing** entries at every binding construct; what is missing is applying
it to the **newly created** entry's own predicate.

**Closed already (do not re-report).** The measure/ADT arm — the one marked with
`meas_sort_prefix` — was fixed on 2026-08-04 by guarding it with
`not (expr_mentions (pat_binders b.A.bind_pat) pred)`. Pinned by
`post-compose-relational` case 3.

## Still open

### 1. The scalar arm (`scalar_sort_of_marker m <> None`)

Reaches the same collision through `reflect_scalar`'s `foreign_var` channel
rather than `load_scope_measure_facts`, so it is older and broader than the
measure path. Reproduced as **`2 proved, 0 violated, 0 skipped`** on
`273b4ef2` **and** on `ad72f67f` (the impossible `needs_lt` goal is proved):

```march
mod PreScalar do
  fn incr(n : Int) : {Int | _ == n + 1} do n + 1 end
  fn needs_lt(u : Int, v : {Int | _ < u}) : Int do 0 end
  fn go(n : Int, u : Int) : Int do
    let n = incr(n)
    needs_lt(u, n)        -- demands n < u for an ARBITRARY u; proved
  end
  fn main() : Int do go(1, 1) end
end
```

The assumption becomes `n == n + 1`, i.e. `false`.

### 2. The record arm (`is_record_sort srt`)

Same producer, same missing test; not reproduced, by inspection only.

### 3. `load_scope_tester_facts`

Accepts the identical `n = x` spelling (`lib/refinecheck/refine_check.ml`, the
tester analogue of `load_scope_measure_facts`) and looks susceptible to the same
shape; not reproduced, by inspection only:

```march
fn keep(o : Option(Int)) : {Option(Int) | is_Some(o)} do o end
...
let o = keep(o)
```

Unlike the measure/scalar cases a bare tester cannot express a contradiction on
its own, so the likely symptom is a **wrong tag attribution** rather than a
vacuous VC — still a false positive, but confirm before assuming.

## Suggested fix

Hoist the guard so it covers all three `postcond` sub-arms — the property is
"a substituted postcondition that mentions this binding's own binder is not
usable at this name", which is arm-independent — then decide separately whether
`is_self_spelling`'s `n = x` clause should be dropped for
postcondition-derived entries generally (it is only sound for parameter
entries). Any change here needs a **paired reject control per arm**: an
accept-only witness cannot distinguish a working contract from one that proves
things vacuously, which is exactly how this survived.

Base-commit evidence and the ADT repro live in
`specs/progress/2026-08-04-refinement-contract-composition-closed.md`.
