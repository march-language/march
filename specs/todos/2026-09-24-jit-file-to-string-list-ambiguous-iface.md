`[P3]` `march --jit file.march`: `to_string` of a `List(Float)` is an internal compiler error

Found 2026-09-24 while triaging [[2026-09-24-jit-to-list-float]]; not fixed there.

This program runs correctly interpreted and under `--compile` (prints
`[3.5, 1.25, 2.]`), but `march --jit` aborts with exit 3:

```march
mod Tlf do
  needs IO.Console
  fn main(_cap_console : Cap(IO.Console)) do
    let xs = NativeArray.to_list_float(NativeArray.from_list_float([3.5, 1.25, 2.0]))
    println(to_string(xs))
  end
end
```

```
march: internal compiler error: March_tir.Llvm_calls.Ambiguous_iface_call("ambiguous
interface-method call to `Show$List.show`: 20 implementations are in scope ...")
Raised at March_tir__Llvm_calls.fail_if_unresolved_iface_method (lib/tir/llvm_calls.ml)
Called from March_tir__Llvm_repl.emit_fns_fragment
Called from March_jit__Repl_jit.run_program
```

So the `--jit` file path (`Repl_jit.run_program` → `Llvm_repl.emit_fns_fragment`)
leaves an interface-method call unresolved that the `--compile` pipeline resolves.
The unresolved call is the `Show` dispatch for the list's element type. Not
checked yet: whether `List(Int)` / `List(String)` hit it too, or only Float
elements.
