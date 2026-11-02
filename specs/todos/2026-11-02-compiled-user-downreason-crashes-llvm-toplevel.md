`[P2]` Compiling a program that declares its own top-level `type DownReason` (a name the
typechecker reserves as a built-in) and matches a built-in `DownReason.Killed` against it crashes
the compiler in `lib/tir/llvm_toplevel.ml` instead of producing a binary or a diagnostic.

Found by the round-2 soundness review of the refinement checker's constructor registry
(`specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md`), probe `c5.march` in the
review scratch area `ctor-review2/`:

```march
mod M do
  needs IO
  fn need1(x : {Int | _ == 1}) : Int do x end
  type DownReason = OnlyR(Int)
  fn f(x : DownReason) : Int do
    match x do
      OnlyR(_) -> 1
      _ -> need1(0)
    end
  end
  fn main(cap : Cap(IO)) : Unit do println(int_to_string(f(DownReason.Killed))) end
end
```

Interpreted it prints `0`. The review observed the compile crash at base `8aaeb6176`, where the
refinement checker (falsely) proved `need1(0)`; since 2026-11-02 that call is reported violated,
which stops `--compile` before codegen. With `need1`'s refinement dropped (`c5n.march`) the
interpreter prints `0` (and warns the `_` arm is unreachable, which it is not) and `--compile`
dies with `internal compiler error: Failure("reserved monitor ABI type DownReason has an
incompatible declaration")`, raised from `Llvm_toplevel.emit_module` (llvm_toplevel.ml:1678).
The typechecker accepts the declaration; the backend should be given a diagnostic, not a crash. Same root as
`specs/todos/2026-11-02-typecheck-conflates-same-short-named-types.md` (the user type and the
built-in are one nominal type to the typechecker); the backend should reject or handle it, not
crash.
