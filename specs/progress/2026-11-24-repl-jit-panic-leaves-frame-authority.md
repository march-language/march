# Native REPL: a panic inside a function with `needs` restricted the rest of the session (2026-11-24)

Found while writing a fixture per authority catch site (pre-1.0 plan, stage A0
step 3). No todo existed.

## Symptom

```
march(1)> fn boom(p : String) : Int needs IO.FileRead("/srv/") do panic("boom") end
march(2)> boom("/etc/hosts")
runtime error: panic: boom
march(3)> Authority.check("IO.FileRead", "/etc/passwd")
```

Input 3 answered `IO.FileRead("/etc/passwd") refused by function boom's needs
(IO.FileRead("/srv/"))`, and so did every later input. The interpreter REPL
(`MARCH_REPL_INTERP=1`) answered `Ok`. The error is on the refusing side: the
session lost authority, it never gained any.

## Cause

`march_repl_guarded` (`runtime/march_runtime.c`), the guard the native REPL runs
each input under, caught the panic and unwound the code-frame stack but not the
authority slot. It was added after ocap phase 4 Task 10b gave every other catch
site a `march_cap_mark` / `march_cap_unwind` pair, and missed it. The panic
skipped `boom`'s `cap_restore`, so the slot kept `boom`'s frame.

## Fix

The guard takes `march_cap_mark()` on entry and calls `march_cap_unwind` on the
panic path, like the other catch sites.

## Test

`test/test_jit.ml`, `repl_session`: "a panic inside a frame leaves the launch
authority", for the JIT (failed before the fix) and the interpreter REPL.
`test/cap_conformance` could not have caught this: its REPL mode runs the
interpreter REPL (`specs/todos/2026-11-17-repl-jit-runs-no-conformance-fixture.md`).
