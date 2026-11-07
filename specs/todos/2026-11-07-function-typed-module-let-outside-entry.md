`[P3]` A function-typed module-level `let` outside the entry module is wrong on native and JS

Found while fixing #1170 (`specs/progress/2026-11-07-js-module-let-value.md`).

```march
mod LetFn do
  needs IO.Console

  mod Cst do
    let inc = fn x -> x + 1
  end

  fn main(_c : Cap(IO.Console)) : () do
    println(int_to_string(Cst.inc(4)))
    let g = Cst.inc
    println(int_to_string(g(5)))
  end
end
```

The interpreter prints `5` and `6`. A native binary prints pointer-sized integers
(`4304714848`), and `--target js` prints `[object Object]`.

The `let` is lowered to a zero-parameter function returning the closure. Both backends
treat a reference to it at a `TFn` type as the function itself (native's TFn arm of
`emit_atom` wraps it in a closure trampoline; JS emits its `$clo` wrapper), and a call
`Cst.inc(4)` passes the argument to the zero-arg function instead of calling it for the
closure and then applying that. The fix probably belongs in lowering (call the zero-arg
fn, then `ECallPtr` the result) so both backends get it.
