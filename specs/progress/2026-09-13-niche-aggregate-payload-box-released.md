# An unboxed aggregate matched out of a niche Option no longer leaks its box

**Landed 2026-09-13.** Filed 2026-09-04 as
`specs/todos/2026-09-04-unboxed-aggregate-niche-payload-leak.md`; that text is
kept below the rule. This is §2 of `specs/2026-09-11-codegen-leaks-design.md`.
The design's release condition turned out to be wrong, and the section after
next explains why.

## The defect (confirmed)

`Some(P2(1.0, 2.0))`, with `type P2 = P2(Float, Float)` unboxed, is
niche-encoded. The inline struct cannot sit in the niche's single pointer
word, so `Llvm_ctx.coerce` boxes it at construction (`march_alloc(32)`), and
that box **is** the `Some` value.

The niche `some` arm in `lib/tir/llvm_case.ml` did three things that together
leave the box with no owner:
- it bound the payload as the raw `ptr`;
- it stripped the scrutinee's `dec_rc`;
- it relied on the binder, whose aggregate type Perceus never drops.

The result was one leaked cell per evaluation: 20,001 over 20,000 iterations,
compiled.

## Two things the design doc got wrong, found by dumping the TIR

1. **The binder's type is not the aggregate.** The pattern compiler binds a
   generic `$f30102 : TVar(_)` (the ctor's declared `a`), and only the
   following `let p : P2 = $f30102` names `P2`. Checking the branch var's
   type never fires. The concrete type is the niche's own payload
   (`Kind.Niche { payload }`), and that is what the fix keys on.
2. **"Replace the stripped dec_rc with an explicit release" has nothing to
   replace.** Perceus puts **no** `dec_rc` of the scrutinee in the `Some`
   arm. When the scrutinee dies, its reference *transfers* to the binder.
   When it is still live, the binder is dup'd:

   ```
   let a = case o of Some($f) -> let p = inc_rc $f; $f in ...   -- o used again
             _ -> panic(...)
   let b = case o of Some($f) -> let q = $f in ...              -- o dies here
             _ -> dec_rc o; panic(...)
   ```

   The dup is inert on a struct slot. So the box must be released exactly
   when the scrutinee dies in this match. Perceus's evidence for that is in
   the **sibling** arms: a dead scrutinee is dropped at the head of every arm
   that does not consume it, whether the `None` arm or the compiler-added
   default.

## What landed

In the niche `some` arm, when the payload's lowered type is an unboxed
aggregate:
- bind a **copy** of the struct (`coerce ptr -> %ub.T`), the boxed path's
  `is_boxed_agg` treatment;
- emit `march_decrc(box)` iff a sibling arm heads with `dec_rc` of the
  scrutinee **and** the body does not `EReuse` the scrutinee's cell. No
  evidence means no release, which is the safe direction.

## Tests

`test/native/niche_aggregate_payload_leak_probe.march` (+ `.expected`,
`test/dune`), four legs of 20,000 each, with values printed:

| leg | shape |
|---|---|
| `spin` | the filed reduction: scrutinee dies in the match |
| `twice` | matched twice; the first match must **not** release |
| `wild` | `Some(_)`, payload never used |
| `keep` | `_` default arm, then a second match |

| build | result |
|---|---|
| unfixed emitter | all four `flat: false` |
| release unconditionally (control) | `RC underflow … aborting` at `twice`, 3 of 3 runs |
| this change | all four `flat: true`; interpreter output identical |

`MARCH_NO_UNBOX=1` is not a usable control from the same file, because the
CAS key does not include it and a rebuild served the unboxed binary. Use a
renamed copy.

---

# Unboxed aggregate stored in a niche-encoded ADT payload leaks

**Filed:** 2026-09-04, while fixing the branch-join leak
(`specs/progress/2026-09-04-unboxed-aggregate-branch-join-leak.md`). Same
feature, same root cause class, different boundary — deliberately not folded
into that fix, because it needs a change in the niche arm's binder handling
rather than at the merge.

## Reproduction

```march
type P2 = P2(Float, Float)
pfn p2sum(p : P2) : Float do match p do P2(a, b) -> a +. b end end

pfn spin(i : Int, acc : Float) : Float do
  if i == 0 do acc else
    let o = Some(P2(1.0, 2.0))          -- no branch needed
    let v = match o do
      Some(p) -> p2sum(p)
      None    -> 0.0
    end
    spin(i - 1, acc +. v)
  end
end
```

`march_live_allocs` delta over the loop, read through an extern:

| build | 5 000 iterations | 20 000 iterations |
|---|---|---|
| current | 5 000 | 20 000 |
| `MARCH_NO_UNBOX=1` (control) | 0 | 0 |

Scales exactly with the loop count, and the control is flat — so it is
attributable to the unboxed-aggregate representation, not to `Option`.

## Mechanism (believed, not yet confirmed at the IR level)

`Llvm_ctx.coerce` boxes the aggregate into the `Some` payload slot
(`march_alloc(16 + 8n)`). `Option(P2)` is niche-encoded, so `Some(x)` **is**
that pointer. In `Llvm_case`'s niche `some_lbl` arm the payload is bound as a
raw `ptr` and the scrutinee `DecRC` is stripped unconditionally ("niche has no
outer box … `Some(ptr)`: stripping is REQUIRED — scrut IS the payload"). The
binder's static type is the aggregate, whose `needs_rc` is false, so Perceus
emits no drop for it either. Nobody frees the box.

Under the boxed representation the payload cell was the `P2` cell itself and
`needs_rc(P2)` was true, so Perceus's drop on the binder released it — which is
why the control is flat.

## Likely shape of the fix

Mirror what the **boxed** path already does for an erased-slot `Float` field
(`boxed_float_field_vals` in `lib/tir/llvm_case.ml`): materialise the value out
of the box eagerly at arm entry — bind the field var as the struct type rather
than as `ptr`, via the existing ptr→struct coerce arm — and then release the
box, so the binder holds a register copy that aliases nothing. The niche path
has no equivalent of that machinery today.

Check before starting: does the same hole exist for a *boxed* ADT payload?
`type Wrap = Wrap(P2, Int)` measured flat in both builds, so the boxed-ADT
field path appears to handle it; the gap looks specific to the niche arm.

## Not this bug

Two leaks found in the same sweep are pre-existing and reproduce identically
with `MARCH_NO_UNBOX=1`, so they are unrelated to this feature: an aggregate
held in a tuple element (2 cells/iteration) and one captured by a closure
(1 cell/iteration).

## Test to add with the fix

A runtime live-object assertion in `test/test_codegen.ml`'s
`unboxed_aggregates` group, in the shape of the two already there — warm the
site, sample `march_live_allocs`, run 20 000 iterations, assert no growth. An
output-only test cannot see this.

> **Design spec (2026-09-11):** `specs/2026-09-11-codegen-leaks-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
