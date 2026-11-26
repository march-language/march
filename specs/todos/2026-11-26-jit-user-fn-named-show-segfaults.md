# `--jit`: a user function named `show` segfaults

Found 2026-11-26 while writing `test/cap_conformance/restrict_actor_kinds.march`.

A module-level function named `show` (the name of the `Show` interface
method) crashes the ORC JIT at run time. The interpreter and a compiled
binary run the same program correctly; renaming the function (`verdict`)
fixes the JIT run.

```march
mod J do
  needs IO.Console
  fn show(r : Result(a, String)) : String do
    match r do
    Ok(_) -> "allowed"
    Err(e) -> e
    end
  end
  fn main() do
    println(show(Ok(())))
  end
end
```

`march --jit j.march` →
`march: fatal SIGSEGV si_code=2 addr=0x9 ... fault outside its stack`, exit 139.
`march j.march` and `march --compile` print `allowed`.

Likely the same family as a module-level fn named like a builtin (the
typechecker and the runtime resolve the name differently): the JIT seems to
dispatch `show(...)` to the interface method / a builtin while the program's
own `show` was typechecked. Fix: make the JIT resolve the user function
first, as the interpreter and the compiled path do, and add a `test_jit` case.
