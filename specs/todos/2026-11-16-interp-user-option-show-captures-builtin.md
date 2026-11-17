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
