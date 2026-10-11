`[P3]` - [ ] **Compiled `to_string` prints a newtype or niche value in a type-variable slot as its payload.**

Filed 2026-10-11, the part of
`specs/progress/2026-10-11-compiled-to-string-newtype-niche.md` that fix did
not cover.

Compiled `to_string` now prints newtype and niche values correctly wherever
the static type reaches the renderer. It still cannot when the value sits in a
slot whose declared type is a type variable of a user generic type, or when
`to_string` is reached with an erased type:

```march
mod Main do
  needs IO.Console
  type Meters = Meters(Int)
  type Box(a) = Box(a)
  fn main(_c : Cap(IO.Console)) do
    println(to_string(Box(Meters(9))))   -- interpreted Box(Meters(9)), compiled Box(9)
  end
end
```

`List`, `Option`, `Result` and tuples are not affected: their Show impls
monomorphise to an element `to_string` with the element's static type.

## Why

The constructor descriptor (`lib/tir/llvm_ctor_desc.ml`) has one entry per
declaration, and a field of type `a` gets the generic token `p`. A boxed ADT
in that slot names itself through its header type id, but a newtype or niche
value has no cell and no header.

## Fix direction

Describe instances: when a call site's static type is a generic user type
whose arguments contain a newtype or niche, add a descriptor entry for that
instance with the substituted field tokens. The descriptor is built at the
first call site that needs it (`Llvm_ctor_desc.ensure_globals`), so either
collect the instances first (a scan of the module's `to_string` arguments) or
emit the descriptor constant at the end of the module. The REPL JIT
finalisers in `llvm_repl.ml` would need the same step.
