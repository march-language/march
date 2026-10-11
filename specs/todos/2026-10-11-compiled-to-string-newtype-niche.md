`[P3]` - [ ] **Compiled `to_string` prints a newtype's payload and a niche's nullary constructor as `nil`.**

Filed 2026-10-11 while working on
`specs/todos/2026-10-07-module-type-layouts.md`.

A type declared directly in the entry module gets the Milestone-2 newtype or
niche layout. Its values have no heap cell, so `march_value_to_string` has no
constructor tag to read and prints the raw payload:

```march
mod Main do
  needs IO.Console
  type Meters = Meters(Int)
  type MaybeName = NoName | Named(String)
  fn main(_c : Cap(IO.Console)) do
    println(to_string(Meters(7)))          -- interpreted Meters(7), compiled 7
    println(to_string(MaybeName.Named("x")))  -- interpreted Named("x"), compiled x
    println(to_string(MaybeName.NoName))      -- interpreted NoName, compiled nil
  end
end
```

Types declared in a nested module are Boxed today and print correctly, which
is the only reason the gap is small. It blocks giving module types their
newtype/niche layouts.

## Fix direction

The static type is known at the `to_string` call site after mono. Either
emit a type-directed printer for TCon arguments whose kind is Newtype/Niche
(including ones nested in lists, tuples and fields, which the runtime walker
reaches without a type), or box such values into their tagged cell at the
`to_string` boundary the way `Llvm_ctx.coerce` boxes unboxed aggregates.
The second only fixes the top level; a `List(Meters)` still prints payloads.
