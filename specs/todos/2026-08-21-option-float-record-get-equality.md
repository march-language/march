# `record_get(...) == Some(<float>)` is always false when compiled

Found re-validating the downstream packages against main `b26bacf0` (after
#317/#321/#323/#324 landed). Interpreted is correct; compiled returns `false`.

This is the last remaining failure in depot's suite
(`test/test_depot_schema.march` — "Float type default in blank", 1341/1342).

## Repro (minimal, no dependencies)

```march
mod Main do
  needs IO
  fn main(cap : Cap(IO)) do
    let r = record_put(record_from_list([]), "z", 0.0)
    let g = record_put(record_from_list([]), "z", 0.5)
    println(record_get(r, "z") == Some(0.0))   -- interpreted: true, compiled: false
    println(record_get(g, "z") == Some(0.5))   -- interpreted: true, compiled: false
    println(record_get(r, "z"))                -- Some(0.) on BOTH
    println(record_get(g, "z"))                -- Some(0.5) on BOTH
  end
end
```

```
$ march repro.march                       # interpreted
true / true / Some(0.) / Some(0.5)

$ march --compile --opt 2 repro.march -o r && ./r
false / false / Some(0.) / Some(0.5)
```

## What this narrows to

- **Not** a value-corruption bug: `println` renders the right float on both
  backends, so `march_record_get`'s payload and the boxed-Option decode are
  both fine. Only `==` disagrees.
- **Not** 0.0-specific. An earlier reading blamed the Float-0.0/None niche
  collision (0.0's bits are 0), but `0.5` fails identically, so the niche
  edge case is not the cause.
- No crash — this is a silent wrong answer, which is the dangerous shape.

So the defect is in the equality path for `Option(Float)` when one side comes
from `record_get` and the other is a literal `Some(<float>)`: the two sides
are presumably built with different representations (the runtime's
`rec_some_k(bits, 'f')` boxed cell vs. the compiled `EAlloc` for
`Some(0.5)`), and `__march_eq_Option_Float` compares them under one
assumption. Dump both with `--emit-llvm` and compare what each side stores at
offset 16 before changing anything.

## Warning for whoever fixes this

An earlier attempt (reverted in #315) "fixed" this by making EVERY `TFloat`
ctor field a boxed `ptr`. That is wrong: boxing is the convention only for a
**generic (`TVar`)** field, while a **concrete monomorphic `Float`** field is
an inline `double` — see `test/native/float_generic_field_abi.march`'s header.
It regressed six native goldens to garbage doubles and wrong arithmetic
(`float_generic_field_abi`, `record_pattern`, `native_arr_map2_inline`,
`native_arr_map_inline_{capture,float_box_reuse,unboxed}`).

**`scripts/run-tests.sh` does NOT run those goldens** — they are dune rules,
so only `dune runtest` covers them. Validate any change here with
`dune runtest`, not `run-tests.sh`.
