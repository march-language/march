`[P3]` - [x] **A non-regular ("nested") datatype hung the compiler; it is now a type error.**

Filed 2026-10-11 as a side note in
`specs/todos/2026-10-11-to-string-erased-newtype.md`; fixed 2026-10-12.

```march
mod Main do
  needs IO.Console
  type Nest(a) = Z(a) | S(Nest(List(a)))
  fn main(_c : Cap(IO.Console)) do
    println(to_string(S(S(Z([[1]])))))
  end
end
```

Interpreted this printed `S(S(Z([[1]])))`. `--compile` and `--dump-tir`
never finished.

## Where it hung

`--timings` got through lower, mono, fusion, defun and perceus, then stopped.
The next pass is deep-drop synthesis (`lib/tir/drop.ml`, `drop_fn_for`). It
memoises one drop function per type instance. Building `__drop$Nest_Int`
needs the drop of its `S` field, `Nest(List(Int))`. That one needs
`Nest(List(List(Int)))`, and so on. Each instance is new, so the memo never
matches and the recursion never ends. A program that only matched on the
value, with no printing, hung in the same place. Printing and equality would
have the same per-instance problem once drop stopped hanging.

## Decision: reject it in the typechecker

Functions over such a type need polymorphic recursion: walking `S(m)` means
calling the function itself at `Nest(List(a))`. HM rejects that
(`specs/lang/core-march-types.md`, "POLYMORPHIC RECURSION IS REJECTED"). So
in either backend a nested datatype can be built but never traversed. Making
the compiled passes handle it by erasure would change drop, printing,
equality and the descriptor tables to support values no user code can
consume. Rejecting the declaration costs nothing a program could use, and it
treats the interpreter the same as compiled code.

`check_nonregular_types` (`lib/typecheck/typecheck.ml`) runs once per
checked module, over each module scope's variant and record declarations.
It expands each type from its own parameters through its constructor fields
and collects the instances of same-scope types it reaches. A regular type
reaches a finite set of instances. That includes own parameters, swapped
parameters (`Swap(b, a)`), a fixed argument (`T(Int)`) and a container of
itself (`Rose(a, List(Rose(a)))`). A nested one keeps producing deeper
instances, and passing a nesting depth of 32 (or 512 instances) reports it.
This also catches growth through a second type
(`A(a) = A2(B(List(a)))`, `B(a) = B1(A(a))`).

The diagnostic has the new code `nonregular_type` and points at the type's
name:

```
type `Nest` refers to itself at a growing type argument, which is not supported [nonregular_type]
```

## Test

`test_compiler`: "non-regular (nested) datatype rejected" checks the direct
case, the mutual case, and that the regular shapes above are still accepted.
It is a typecheck-only test, so it finishes at once.
