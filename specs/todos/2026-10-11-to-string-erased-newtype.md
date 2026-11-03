`[P3]` - [ ] **Compiled `to_string` on an erased type prints a newtype or niche value as its payload.**

Filed 2026-10-11, the part of
`specs/progress/2026-10-11-to-string-newtype-in-generic-slot.md` that fix did
not cover.

```march
mod Main do
  needs IO.Console
  type Meters = Meters(Int)
  type Box(a) = Box(a)
  fn main(_c : Cap(IO.Console)) do
    let f = fn x -> to_string(x)
    println(f(Meters(1)))        -- interpreted Meters(1), compiled 1
    println(f(Box(Meters(2))))   -- interpreted Box(Meters(2)), compiled 2
  end
end
```

## Why

The let-bound lambda is not specialised, so its `to_string` sees a `TVar`
and calls the untyped `march_value_to_string`. A boxed ADT names itself
through its header type id, but a newtype or niche value has no cell, so
there is nothing to read.

## Fix direction (needs a design decision)

Either specialise such lambdas per use type, or pass a runtime type
descriptor with an erased value (a dictionary argument for `to_string`, or a
type id carried by the closure). Both change how erased code is compiled, so
this was not done as part of the printing fix.

Also seen while filing: compiling a polymorphically recursive type
(`type Nest(a) = Z(a) | S(Nest(List(a)))`) hung in deep-drop synthesis. That
type is now rejected at its declaration; see
`specs/progress/2026-10-12-nonregular-type-compiler-hang.md`.
