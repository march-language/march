`[P2]` A default method of an impl declared in another file than its interface is unbound
at run time. With `interface Sem(a)` and its default `fn twice : a -> a do fn x ->
combine(x, x) end` in `lib/alg.march`, and `impl Sem(Int)` defining only `combine` in the
entry file, `twice(21)` fails in the interpreter with "unbound variable: twice". The check
passes. `Desugar.inject_defaults` runs per file, so the impl's file never sees the default.
Found while testing interface laws (`specs/progress/2026-11-03-laws-across-files.md`), whose
own copies handle the case.
