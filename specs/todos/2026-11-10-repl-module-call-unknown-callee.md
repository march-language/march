# The REPL cannot call a function of a module declared at the prompt

Found 2026-11-10 (ocap phase 3 probes). In `march repl`:

```
march(1)> mod Dep do
  needs IO.Console
  fn slurp(p : String) : String do
    match File.read(p) do
      Ok(s) -> s
      Err(_) -> "none"
    end
  end
end
march(2)> Dep.slurp("/nonexistent")
error: March_tir.Llvm_calls.Unknown_callee("`Dep.slurp` is not a function in scope and not a runtime builtin")
```

The declaration is accepted; the call fails in the JIT's fragment compilation.
