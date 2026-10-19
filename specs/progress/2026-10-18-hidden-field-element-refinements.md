Refinements: a constructor field that hides a demanded type parameter is a recorded skip, not vacuously true (multi-arg design phase 0)

Phase 0 of `specs/2026-10-18-abstract-refinements-multi-arg-design.md` (§0 finding F5,
rows h1/h2). Soundness fix, independent of phases 1-4.

## Before / after

```march
mod Q do
  type Wrap(k, v) = Wrap(List((k, v)))
  fn mk() : Wrap(Int, {Int | _ > 0}) do Wrap([(1, 0 - 5)]) end
  fn need(_w : Wrap(Int, {Int | _ > 0})) : Int do 0 end
  fn use_mk() : Int do need(mk()) end                  -- h1
  fn use_lit() : Int do need(Wrap([(1, 0 - 5)])) end   -- h2
end
```

| | Before (`ba8db5805` + design commits) | After |
|---|---|---|
| h1 | `1 proved, 0 skipped`: a false proof, also under `cap verified` | `return of mk` and `need`: both skip, `unreflectable-subject`; under `cap verified`, two errors |
| h2 | no obligation at all, accepted under `cap verified` | `need`: skip, `unreflectable-subject`; error under `cap verified` |
| leftovers design Q4: `type Dq(a) = Dq(Int, List(a), List(a))`, `fn mk_bad() : Dq({Int \| _ > 0}) do Dq(1, [0 - 1], []) end` | 0 obligations, silently unenforced | two skips (one per `List(a)` field), `unreflectable-subject` |

The skip detail names the constructor and the hiding type:
"`Wrap`'s field holds `v` inside `List((k, v))`, which the element model does not see into".

## Cause

The `ECon` arm of `check_elements` (`lib/refinecheck/refine_check.ml`) checked `Param i`
fields against slot `i`, recursed into `Self` fields, and returned `true` for every `Other`
field. That held even when the field's type mentioned a type parameter whose slot was
demanded. A field such as `List((k, v))` holds `v` values outside every element slot, so
nothing about them was checked. A tail checked this way also entered `elem_ret_proved`, so
`mk()`'s declared element return was then trusted at every call site (h1).

## Fix

- New table `ctor_field_params` (`lib/refinecheck/refine_encode.ml`, filled in
  `register_field_sorts` for user variants and cleared with `ctor_param_fields`). It maps
  each constructor field to the type parameters its declared type mentions, plus the field
  type rendered for messages. The builtins (`Cons`, `Some`, `Ok`, `Err`) have no such
  field and are absent.
- In the `ECon` arm, an `Other` field that mentions a parameter whose demanded slot is
  `Some` goes through `record_elem_skip` (`unreflectable-subject`). That escalates under
  `cap verified`, and the arm returns `false`. A `false` tail keeps the function out of
  `elem_ret_proved` (`gate_elem_returns`).
- An `Other` field mentioning only undemanded parameters (or none) is still owed nothing.
  The same goes for a construction of a hidden-parameter type whose demand refines no
  slot.

Phase E of `specs/2026-10-18-abstract-refinements-leftovers-design.md` refines this
conservative floor: it models nested `List(a)` fields so that Q4 becomes a violation.

## Tests

`test/test_refinecheck.ml`, group `hidden-field-elements` (6 cases). RED is measured on the
base commit with only the test file applied.

| Case | Base | Fixed |
|---|---|---|
| h1: hidden-field return is a skip, not a proof | FAIL (received `[("mk(…)", "proved", "")]`) | OK |
| h1 under `cap verified` is an error naming the constructor and the hiding type | FAIL | OK |
| h2: hidden-field literal files an obligation and skips | FAIL | OK |
| an undemanded hidden parameter owes nothing | OK (control) | OK |
| Q4: `Dq(Int, List(a), List(a))` construction is a recorded skip | FAIL | OK |
| controls: `Assoc` / `Cons` / `Some` literals still prove and still violate | OK (control) | OK |

## Verification

- `dune build --root .`: ok.
- `./_build/default/test/test_refinecheck.exe -e` (VC cache cleared once, z3 4.16.0):
  1035 tests, all pass, 0 SKIP.
- `scripts/run-tests.sh -q compiler`: 1348 tests, all pass.
- `scripts/refine-oracle.sh`, with the baseline recorded on the base commit in a separate
  worktree and both runs under the script's private HOME: **identical**, 7786 lines over
  549 fixtures. The corpus has no hidden-field construction that a refined element is
  demanded through, so no line moves.
- CI ratchet (`--check --stdlib-source --refine-report stdlib/list.march`, cold
  artifacts): `user + stdlib` is 63 proved / 33 trusted / 37 skipped both before and after,
  against a ceiling of 42. Byte-identical report.
- Audit baselines (`test/refine_audit/*.baseline`, group `audit-baseline` in the run
  above): unchanged, not regenerated.

## Stdlib fallout

None. The stdlib slice of every probe's `--refine-report-sites` output is byte-identical
before and after (87 proved, 43 skipped). No stdlib function declares an element-refined
return on a hidden-parameter container (`Map`'s `HamtMap(HEntry(k, v))`, `Deque`), so no
stdlib element return was a false proof that this fix withdraws. A definition-side element
return inside `map.march` would now be a skip, not a vacuous proof. That is the
precondition the design's phase 4 needed.

## Filed

- `specs/todos/2026-10-18-elem-slot-naming-parameter-false-violation.md` (row r7).
- The permuted-`Self` hole, filed and then fixed (see the follow-up section below).

## Follow-up: permuted and non-parameter self-references

A `Self` field whose type arguments are not the declared parameters in order
(`N(T(b, a))`, `UN(U(List(a)))`) was still checked as the same container with the same
slots. A `match` binder at such a field also took the outer entry, which gave a false
proof. A follow-up commit closes both, the same way as phase 0:
`specs/progress/2026-10-18-elem-permuted-self-field-unchecked.md`.
