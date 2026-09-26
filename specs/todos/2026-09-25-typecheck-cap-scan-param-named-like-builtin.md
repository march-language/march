# `[P3]` Typecheck capability scan: a parameter named like a capability builtin is charged as the builtin

Filed 2026-09-25 from the work on
`specs/progress/2026-09-25-user-fn-named-like-builtin-symbol.md`.

A program that has a parameter (or other local binding) named like a builtin that
needs a capability, for example `fn go(file_read : String -> String) do file_read("x") end`,
and **no** top-level function of that name, is rejected on both backends:

```
function bodies in `M` call builtins that require `Cap(IO.FileRead)`
```

The call is to the local, not the builtin, so no capability is involved. The TIR-side
walk (`Cap_attrib.walk` in `lib/tir/cap_attrib.ml`) was taught to treat parameters
and local bindings as locals in that change. The typecheck-side scan that produces
this diagnostic still matches by bare name.

Fix: make the typecheck capability scan scope-aware the same way (a name bound by a
parameter, `let`, pattern or lambda shadows the builtin). The test should accept the
program above, and still reject a real `file_read(...)` call made without the
capability, so an accept-only test cannot pass by never charging anything.
