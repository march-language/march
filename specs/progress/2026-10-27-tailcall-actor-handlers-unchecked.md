## Completed 2026-11-07

The tail checker now visits non-recursive function bodies and actor handler
bodies, using an empty enclosing recursion set. Named local functions still
receive their own recursion set. Lambda bodies and `let*` continuations are
visited with fresh empty sets, preserving their call-frame boundary.

Regressions cover rejection in ordinary functions, actors, nested named locals,
lambdas, and `let*` continuations; safe actor tail recursion, structural warnings,
callback calls to the enclosing function, and the existing opt-out remain intact.

## Original report

`[P3]` The stack check never visits actor handler bodies

Filed 2026-10-27 by phase 0 of `specs/2026-10-26-termination-checking-design.md`
(fact F3, row t12). This is about stack safety, not termination.

`enforce_tail_calls_in_decls` (`lib/typecheck/typecheck_tailcall.ml`) has arms for `DFn`
and `DMod` declarations only. A `DActor`'s handler bodies are never walked. So a
recursive local `fn` declared inside a handler, with a non-tail self-call, gets no
`non_tail_recursion` diagnostic. A handler itself cannot recurse by name, since it
is not callable. The gap is therefore the local functions declared inside handlers. A top-level helper
that a handler calls is already covered as an ordinary `DFn`.

`Refine_term` (`lib/refinecheck/refine_term.ml`) already treats a handler as a unit
and walks its body, so `--termination-report` lists such a local `fn`.

Fix: add a `DActor` arm that runs the local-`fn` walk of
`2026-10-27-tailcall-local-fn-in-nonrecursive-fn-unchecked.md` over each handler
body (`March_ast.Ast.actor_body_handlers`).
