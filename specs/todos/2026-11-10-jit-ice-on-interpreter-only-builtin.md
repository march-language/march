# `--jit` exits with an internal compiler error on an interpreter-only builtin

Found 2026-11-10 by `test/test_cap_mode_parity.ml` (fixture `unlowerable`). The interpreter runs
this program; `--compile` refuses it with a positioned `compiled_unsupported` error; `--jit`
lowers it, the same `Diagnostic_exn` escapes, and the driver prints
`march: internal compiler error: ... [compiled_unsupported]` with an OCaml backtrace and exit 3:

```march
mod Main do
  needs IO.Console
  fn main(c : Cap(IO.Console)) do
    println("before")
    App.stop()
    println("after")
  end
end
```

`--jit` should either fall back to the interpreter with a notice (as it does for actor programs)
or render the diagnostic and exit 1. The driver's `jit_run` guard in `bin/main.ml` is the place.
