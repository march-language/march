`[P2]` Interpreter: a user `type Option` with `derive Show` captures the builtin `Option`'s `show`

```march
mod Main do
  needs IO.Console
  type Option = Has(Int) | Empty
  derive Show for Option
  fn main(c : Cap(IO.Console)) do
    print_line(to_string(Has(3)))
    print_line(to_string(List.head_opt([1])))
  end
end
```

- Interpreted: prints `Has(3)`, then panics: "Non-exhaustive pattern match: no branch matched the
  value Some(1)". `to_string` of the builtin `Some(1)` runs the user's derived `show`.
- `--compile` (since the fix in
  `specs/progress/2026-11-11-compiled-derive-on-user-type-named-like-prelude-type.md`): `Has(3)`,
  `Some(1)`.

The interpreter's impl dispatch keys the derived impl by the short type name, so the user's
`Show(Option)` replaces the prelude's `Show(Option(a))`. Reproduces on `bd2ff7958`.

## Fixed 2026-11-19

**Root cause.** The interpreter keys a type's impls and constructors by short name, qualified by
the module prefix only for a colliding name (`compute_type_collision_set`, `lib/eval/eval.ml`).
The builtin ADTs are seeded as a prefix-"" candidate, and the entry module and the prelude are
both unwrapped to the top level, so a top-level user `type Option` has prefix "" too:
`add_qualified` deduplicates it into the builtin's own entry, the name never counts as
colliding, `Has` registers as plain `Option`, and the derived impl writes the bare
`("Show", "Option")` slot (the DImpl arm's `dispatch_type_name`, `:4117` on `2805ec479`) over the
prelude's `impl Show(Option(a))`. `to_string(Some(1))` then ran the user's `show`.

**Fix.** The interpreter now gives the entry module's own top-level variant named like a builtin
ADT the typechecker's identity (`Main.Option`, `entry_shadow_identity`). A top-level `DType` of
one of those names is always the user's (no stdlib file declares one); a top-level impl is the
user's when its declaration is in that type's file (the prelude's impls are in `prelude.march`;
a derived impl's span is the derive site). `register_type_ctors` records the user's constructors
under that identity in `ctor_qualified_type_tbl` (a constructor spelled like the builtin's, as in
`type Option(a) = Some(a) | None`, is marked ambiguous instead), and the impl claims the
qualified slot, leaving the prelude's bare slot alone (`bare_slot_exact`). Constructor tags are
unchanged.

Regression: `test/test_codegen.ml` "top-level `type Option` derive Show leaves the builtin's"
(`Has(3)`, `Nada`, `==` on both types, `List.head_opt`, `string_to_int`; interpreted and compiled
at `--opt 0` and `2`). RED before the fix: the reported panic.
