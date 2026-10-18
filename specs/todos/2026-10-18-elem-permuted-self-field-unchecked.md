# Element refinements: a permuted `Self` field is checked against the wrong slots

Found 2026-10-18 while landing phase 0 of
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
