`[P3]` The TUI REPL prints `val f = <fn>` for a function the JIT failed to compile (2026-11-23)

From reading the source; not run.

lib/repl/repl.ml has two near-copies of the prompt loop. For a function declared at the prompt:

- the plain loop (about line 1090) calls `Repl_jit.run_decl` and lets a `Failure` surface as
  `jit error: ...`;
- the TUI loop (about line 1699) wraps the same call in `try ... with Failure _ -> ()`, then
  still updates the type environment and prints `val f = <fn>`.

So in the TUI a declaration that failed (for example the polymorphic function in
2026-11-11-repl-nested-fn-decl-jit-error-hd.md) looks defined, and the failure appears later, at
the first call, with no link to its cause. Piped-stdin tests exercise only the plain loop, so no
test sees the difference.

Fix: factor the prompt-declaration dispatch into one function used by both loops (no behaviour
change in the plain loop), so every later REPL fix is a single edit. This is step 2 of unit U8 in
specs/plans/2026-11-23-pre-1.0-bug-first-plan.md.
