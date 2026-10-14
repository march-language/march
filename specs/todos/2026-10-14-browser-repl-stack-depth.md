`[P2]` Browser REPL: "Maximum call stack size exceeded" on modest recursion (2026-10-14)

The in-browser interpreter (docs/assets/march.js, js_of_ocaml) runs out of JS stack
far below what native March handles. On the 2026-10-14 release bundle, and the same on
the July bundle before it, under Node (about 1 MB default stack, similar to browsers):

- `List.length(List.map(List.range(0, N), fn x -> x + 1))` fails for N = 500.
- Building a `Map` by folding over `List.range(0, 1000)` fails; 500 works.

For a learning REPL this is severe: ordinary list examples a reader writes will fail
with `error: Failure("RangeError: Maximum call stack size exceeded")`.

Leads, all untested:
- Find where the interpreter recurses per list element (`List.map` and `range` in
  the prelude, and `Eval.eval_expr` / `apply` depth).
- js_of_ocaml's tail-call handling: `--enable effects` is not wanted (see `js/dune`),
  but mutual tail calls may compile to JS recursion.
- Catch the RangeError and report "too deep for the browser REPL" instead of the raw
  Failure, as the Int overflow work did for 32-bit Int.

Reproduce: `scripts/browser-repl-node.js`'s `loadRepl('docs/assets').run(...)`.

Also seen in the same session: `UUID.v4()` fails with a raw `/dev/urandom` error in
the browser; it could use `crypto.getRandomValues`.
