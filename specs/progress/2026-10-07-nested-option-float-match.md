# `[P1]` A function matching `Option(Option(Float))` and returning `Float` returns garbage when compiled

**FIXED 2026-10-07.** Found while checking the nested-pattern ctor-name collision fix (PR #868,
`specs/todos/2026-10-07-option-option-float-return-garbage.md` on that branch).

## Problem

```march
mod Main do
  needs IO.Console
  pfn of(o : Option(Option(Float))) : Float do
    match o do
      Some(Some(f)) -> f
      Some(x) -> 0.5
      None -> 0.0
    end
  end
  fn main(_c : Cap(IO.Console)) : () do
    println(float_to_string(of(Some(Some(2.5)))))
    println(float_to_string(of(Some(None))))
  end
end
```

Interpreted: `2.5`, `0.5`. Compiled: two denormals (`2.97780667276e-311`, ...).
`Result(Option(Float), _)` with `Ok(Some(f))` beside `Ok(x)` did the same, and so did a
generic `Option(Option(a))` match instantiated at `Float`.

## Root cause

Not the result join the todo suspected. The INNER match decoded the wrong representation.

`lib/tir/lower_match.ml`, `compile_matrix_impl`: the sub-pattern variable for `Some`'s
field is minted at `unknown_ty` (`TVar "_"`) whenever another row binds that field to a
plain name (`field_ty_at`; here `Some(x)`), so the nested `ECase` on it reached
`Llvm_case.emit_case` with an erased scrutinee. Its erased-scrutinee recovery
(`branches_match_niche_shape`) sees branch tags `Some`/`None`, finds the only owner
`Option` niche-shaped, and commits to the NICHE decode: null = `None`, non-null = the
payload itself. An `Option(Float)` is niche-UNSAFE (`0.0` is all-zero bits), so it is a
boxed cell: `Some(None)`'s inner `None` cell (non-null) was taken as `Some`, and every
`Some` cell was unboxed as if it were the payload's float box, which is where the denormal
came from. The constant arm never ran. Without the name-binding row (`Some(None) -> 0.5`)
the sub-variable keeps the pattern's type, the match takes the boxed decode, and the
program was already right.

## Fix

`Lower_match.case_scrut_ty`: when a constructor column's scrutinee atom is erased, the
`ECase` built for that column switches on the same variable re-annotated with the type the
typechecker recorded for the column's constructor pattern (the same in-place
re-annotation `expand_record_column` already does for a nested record). The sub-variable's
binding, and every `let x = <sub_var>` rebinding of a name-bound row, keeps the erased type,
so the uniform-to-natural untag `field_ty_at` protects is unchanged. Codegen then sees
`Option(Float)` and decodes it boxed, exactly like the already-correct typed path; a
polymorphic `Option(Option(a))` is substituted by mono like any other annotated type.

Sibling paths checked: the record column already re-annotates (`expand_record_column`);
tuple columns carry their own `$TupleN` handling; the default (name-binding) path is
deliberately left erased.

## Verification

- `test/native/nested_option_float_match.march` (+ `.expected`, the interpreter's output;
  dune rule `native_nested_option_float_match`): `Option(Option(Float))` returned directly,
  through a `let`, and through a nested case arm; `Option(Option(Int))`;
  `Option(Option(String))`; `Result(Option(Float), String)`; a generic `Option(Option(a))`
  at `Float` and `Int`. RED on `origin/main` (11 of 22 lines are denormals or wrong), GREEN
  with the fix.
- TIR snapshots unchanged.

## Left open

A dropped `Option(Option(Float))` / `Result(Option(Float), _)` still leaks the inner Float
box (1 object per `Some(Some(f))`), with or without this fix and for the already-typed
match too: `specs/todos/2026-10-07-option-float-payload-shallow-drop.md`. This fix halves
that leak for the name-binding shape (400 -> 200 objects over 200 calls).
