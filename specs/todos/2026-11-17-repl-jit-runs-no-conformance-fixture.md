# The REPL's JIT engine cannot run the run-time authority conformance fixtures

Logged 2026-11-17 by ocap phase 4, Task 7 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md).

`test/run_cap_conformance.ml`'s `repl` mode runs `march repl --grant G <fixture>` with
`main`'s body typed at the prompt under `MARCH_REPL_INTERP=1`, the interpreter engine. The
default engine, the JIT, cannot run a single fixture, for reasons that predate ocap phase 4
(each reproduced on main @ d06fb7f64 as well):

- **A preloaded file's fns are not compiled.** `march repl file.march` loads its
  declarations flat through `load_decls_list`, which registers only a `mod` with the JIT
  (`register_module_decl`); a later prompt line calling one of its fns fails with
  `Llvm_calls.Unknown_callee("`verdict` ... is not a function in scope")`.
- **A `mod` typed at the prompt is not compiled either.** The prompt's declaration path
  evaluates a `DMod` in the interpreter only; `Foo.twice(4)` then fails the same way.
  (`:load file` does register it, but wraps it in a module, so its fns are qualified and a
  frame's refusal names `G.in_srv`, not `in_srv`.)
- **`use Mod.*` at the prompt** is read as incomplete input (it ends in `*`) and swallows
  the next line; `use Mod.{f}` typechecks, but the JIT then cannot resolve `f`.
- **A polymorphic fn declared at the prompt** is never instantiated, so the fragment has
  no body for it (specs/todos/2026-11-11-repl-nested-fn-decl-jit-error-hd.md). On this
  branch it crashed instead (the fragment also carries lifted Authority-policy lambdas,
  and `run_decl` bound the first of them to the name); Task 7 made it a clean
  `jit error: no compiled body for `f``.
- **`let y = one()`, `one` a fn declared at the prompt**, fails: the JIT let path's error
  is swallowed and the interpreter, which never saw `one`, reports
  `runtime error: unbound variable: one`.

Repro (each `| march` reads stdin as a REPL session):

```
printf 'mod Foo do\n  fn twice(x : Int) : Int do x * 2 end\nend\nFoo.twice(4)\n' | march
printf 'fn one() : Int do 1 end\nlet y = one()\ny\n' | march
```

What to do: register a preloaded file's and a prompt `mod`'s fns with the JIT, instantiate
(or interpret) a polymorphic prompt fn, and make the JIT let path either work or fall back;
then drop `MARCH_REPL_INTERP=1` from the conformance runner's `repl` mode, so the REPL's C
launch (`launch_repl_authority`'s JIT half) and the JIT capture items of
specs/todos/2026-11-16-ocap-p4-capture-gaps.md are pinned too.
