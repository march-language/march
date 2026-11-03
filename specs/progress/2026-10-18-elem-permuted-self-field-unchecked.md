# Element refinements: a permuted `Self` field is checked against the wrong slots

Found and fixed 2026-10-18, in a follow-up commit to phase 0 of
`specs/2026-10-18-abstract-refinements-multi-arg-design.md`
(`specs/progress/2026-10-18-hidden-field-element-refinements.md`).

```march
mod Q do
  cap verified
  type T(a, b) = L(a) | R(b) | N(T(b, a))
  fn need(_t : T({Int | _ > 0}, Int)) : Int do 0 end
  fn go() : Int do need(N(R(0 - 1))) end
end
```

`march --check --refine-report` reports 0 obligations, and the program is accepted under
`cap verified`. That is a silent hole: the `-1` inside `R` is a value of the outer `a`,
which is demanded `_ > 0`. `register_field_sorts` (`lib/refinecheck/refine_encode.ml`)
gives role `Self` to any field whose type constructor is the type itself, whatever its
arguments are. The `ECon` arm of `check_elements` then recurses with the SAME slots, but
`N`'s field is `T(b, a)`, so its slots are permuted. `ctor_hidden_params` already treats a
non-identity self-reference as hiding its parameters. The fix is either to permute the
slots for the recursion (when the arguments are a permutation of the parameters), or to
apply phase 0's rule: a recorded `unreflectable-subject` skip whenever such a field
mentions a demanded parameter.

The `match` side had the same hole, and it was worse: a false proof. In
`match t do N(inner) -> needt(inner) end` with `t : T({Int | _ > 0}, Int)`, the binder
`inner` took `t`'s whole entry. `inner` is really a `T(Int, {Int | _ > 0})`, yet
`needt(inner)` was counted `proved`.

## Fix

Conservative, as phase 0 is. The slots are not permuted.
- `ctor_field_params` (`lib/refinecheck/refine_encode.ml`) now records the parameters
  each field HIDES. That is nothing for a `Param` field or an identity self-reference, and
  every parameter mentioned for any other field, including a permuted self-reference
  (`N(T(b, a))`) or a non-parameter one (`UN(U(List(a)))`). It shares one `hidden_of` with
  `ctor_hidden_params`, so the two cannot disagree.
- In the `ECon` arm of `check_elements`, a `Self` field that hides a demanded parameter
  gets the same `unreflectable-subject` skip as an `Other` field: "`N`'s field holds `a`
  inside `T(b, a)`, which the element model does not see into". An identity `Self` field
  still recurses.
- In `match` facts, a `PatVar` at a `Self` field takes the scrutinee's entry only when
  that field hides nothing. Dropping a have-side fact is always sound.

## Tests

These are in `test/test_refinecheck.ml`, group `hidden-field-elements`. RED was measured
on a5384fa85 with only the tests applied.

| Case | a5384fa85 | Fixed |
|---|---|---|
| a permuted Self field is a recorded skip (`needt(N(R(0 - 1)))`; error under `cap verified`) | FAIL (received `[]`) | OK |
| a match binder at a permuted Self field carries no element fact | FAIL (received `[("inner", "proved", "")]`) | OK |
| a non-parameter Self field is a recorded skip (`needu(UN(UL([0 - 1])))`) | FAIL (a skip, but for the wrong reason: `sort-conflict`) | OK |
| control: an identity Self field still recurses (proves and violates) | OK | OK |
| control: a match binder at an identity Self field keeps the entry | OK (after fixing the expected callee label to `rest`, the subtyping arm's label) | OK |

The review's other probed paths are pinned in the same group: `if` and `match` tails of
hidden-field constructions, `Some(Wrap(..))`, `[Wrap(..)]`, mixed `P(a, List(a))`, and a
`let`-bound construction passed on. All of them passed on a5384fa85.
