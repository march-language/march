`[P2]` Native equality on a newtype wrapping a generic named record uses pointer identity.

Found 2026-11-06 while fixing record equality helper collisions. This is a
separate failure: the generated `__march_eq_Wrap_String` calls
`march_poly_eq` on its raw record payload, rather than a structural record
helper. The payload remains `TCon("Cell", [TString])`; the equality generator
cannot resolve the named generic record into its fields.

```march
mod GenericRecordEq do
  needs IO.Console
  type Cell(a) = { value : a }
  type Wrap(a) = Wrap(Cell(a))
  derive Eq for Cell
  derive Eq for Wrap
  fn main(_cap_console : Cap(IO.Console)) do
    let a : Cell(String) = { value: "ann" }
    let b : Cell(String) = { value: "bob" }
    let c : Cell(Int) = { value: 1 }
    let d : Cell(Int) = { value: 2 }
    println(bool_to_string(Wrap(a) == Wrap({ value: "ann" })))
    println(bool_to_string(Wrap(a) == Wrap(b)))
    println(bool_to_string(Wrap(c) == Wrap({ value: 1 })))
    println(bool_to_string(Wrap(c) != Wrap(d)))
  end
end
```

Interpreted output: `true`, `false`, `true`, `true`.
Compiled output: `false`, `false`, `false`, `true` (exit 0).
Reproduced with the compiler based on b7c963d74. Inspect the named-record
resolution used by `lib/tir/llvm_eq.ml` before changing the runtime comparator.
