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
