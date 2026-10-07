`[P1]` A function matching `Option(Option(Float))` and returning `Float` returns garbage when compiled

Found 2026-10-07 while checking
[../progress/2026-10-07-nested-pattern-ctor-name-collision-miscompile.md](../progress/2026-10-07-nested-pattern-ctor-name-collision-miscompile.md).
Present on main before that change (same output with and without it).

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

Interpreted: `2.5`, `0.5`. Compiled: two denormals (`2.44394237244e-311`, ...): even the
constant arm `Some(x) -> 0.5` is wrong, so the fault is in how the function's result
joins, not only in the payload decode. `--emit-llvm` shows `define double @of` with a
`ptr` result slot that the `None` arm fills with `march_alloc_float(0.0)` (a box), i.e. the
arms store boxed floats and the return reads the slot as a raw double. `Option(Float)` is
niche-unsafe, so the inner option is a boxed cell inside a niche outer option; the case
result-slot typing (`Llvm_case`'s join / `predicted_unboxed_tail`) does not account for it.
