`[P3]` - [x] **Compiled `to_string` prints a newtype or niche value in a type-variable slot as its payload.**

Filed 2026-10-11, the part of
`specs/progress/2026-10-11-compiled-to-string-newtype-niche.md` that fix did
not cover. Landed the same day.

## What was wrong

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

The constructor descriptor (`lib/tir/llvm_ctor_desc.ml`) had one entry per
declaration, and a field of type `a` got the generic token `p`. A boxed ADT
in that slot names itself through its header type id, but a newtype or niche
value has no cell and no header, and a tagged Bool reads as an Int. So, in a
type-variable slot of a user generic type: `Box(NoName)` printed `Box(nil)`,
`Box(true)` printed `Box(1)`, `Pair(Flag(false), ..)` printed `Pair(0, ..)`.
A generic niche (`type Opt(a) = Nada | Has(a)`) had no row at all, so
`Has(4)` printed `4` and `Nada` printed `nil`.

`List`, `Option`, `Result` and tuples were not affected at the top level:
their Show impls monomorphise to an element `to_string` with the element's
static type.

## The change

The descriptor now describes INSTANCES. When a static type is a generic type
applied to ground arguments (`TCon (name, args)`, no `TVar` in `args`),
`Llvm_ctor_desc.id_for_ty` adds an instance row with the arguments
substituted (`instance_id`):

- a slot whose declared type is a type variable gets `erased_token` of the
  argument: `I`/`B` for a tagged Int/Bool, `u` for Unit, `p` for a Float
  (a boxed cell the generic renderer reads), else the argument's own token;
- any other slot gets the substituted type's ordinary token, so a declared
  field of type `List(a)` names the `List(Meters)` instance;
- the instance's kind comes from `Kind.repr_of` WITH the arguments for a
  niche-shaped type (`Opt(Meters)` is `X`, `Opt(Float)` is a boxed `V`), and
  from the declaration otherwise.

The instance is registered before its rows are built, so a recursive type
(`Tree(Meters)` inside `Node`) names itself. At most 512 instances per unit
(`max_instances`), which bounds a polymorphically recursive type; past that a
slot keeps the declaration's row.

Instances are found at call sites, after the first site has already asked for
the descriptor, so the descriptor string is no longer interned at the first
call: `ensure_globals` only names it, and `Llvm_ctor_desc.flush` defines it
after the last function body. `Llvm_toplevel.emit_module` and the five
`Llvm_repl` fragment finalisers call `flush`.

Runtime (`runtime/march_extras.c`): an instance's kind is written with a
trailing `*` (`V*`, `N*`, `X*`). An instance is never registered under the
header type id, since the header names only the declaration, and
`ctor_render` keeps an instance id over the header's when both name the same
type.

## Test

`test/native/to_string_generic_instance.march` runs interpreted and compiled
against one `.expected` (29 lines: newtype, niche, Bool, Float, Unit and ADT
in a type-variable slot, multi-parameter and recursive generic types, generic
niches boxed and not, a declared field of an applied generic type, a record
field, List/Option elements, interpolation, `inspect`, `~H`).

## Left open

`specs/todos/2026-10-11-to-string-erased-newtype.md`: a `to_string` whose
argument type is erased (a let-bound lambda, `let f = fn x -> to_string(x)`)
still prints a newtype or niche value as its payload. There is no static type
at that site, so this needs a runtime type descriptor (a design decision).

Found on the way, not caused by this change: compiling a polymorphically
recursive type (`type Nest(a) = Z(a) | S(Nest(List(a)))` with
`S(S(Z([[Meters(1)]])))`) hangs before codegen (`--dump-tir` hangs too).
