`[P3]` REPL: `let n = LazyNicheProbe.first_or(...)` is "unbound variable" at run time (2026-11-25)

At the `march repl` prompt a bare call into a lazily loaded module works
(`LazyNicheProbe.first_or([7, 8], 3)` prints `= 7`), but binding its result fails:

```
march(1)> let n = LazyNicheProbe.first_or([7, 8], 3)
runtime error: unbound variable: LazyNicheProbe.first_or
```

The call typechecks (since 2026-11-25 at the function's annotated type, see
`progress/2026-11-25-registry-loaded-module-fn-untyped.md`, where this symptom was first
listed). The `let` path evaluates the right-hand side somewhere the lazily loaded module's
definitions are not present, while the expression path loads them.

`lazy_niche_probe.march` is the only lazily loaded stdlib file and is a compiler fixture,
so a user meets this only by calling it. Fix where the REPL evaluates a `let`: load the
module the way the expression path does. Test: the session above in `test/test_jit.ml`,
expecting `val n = 7`.
