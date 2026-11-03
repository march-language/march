Browser REPL: "Maximum call stack size exceeded" on modest recursion (2026-10-14) — FIXED

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

## Fixed (2026-10-14)

**Root cause.** The browser interpreter recursed on the JS stack.
- Every March call is a chain of evaluator frames (`eval_expr` → `apply` →
  `eval_expr` …), about 1.2 KB of JS stack each.
- js_of_ocaml turns only direct self-calls into loops, not the evaluator's calls
  through closures. So tail calls grew the stack too.
- A browser gives about 1 MB, so the limit was a few hundred March calls:

| Workload | Limit before |
|---|---|
| `List.range` | 243 elements |
| `List.map` | 195 elements |
| A tail-recursive loop | 805 calls |
| Non-tail recursion | 626 levels |

The native interpreter does the same recursion, but with smaller frames and an
8 MB stack. A tail-recursive count still overflows natively at 10,000,000.

**Fix.** `js/dune` compiles `march_browser` with `--effects=cps`. The continuation
lives on the heap and js_of_ocaml bounces off the stack when it gets deep, so depth
is bounded by memory.

Measured in Node, all of these now complete:

| Workload | Result |
|---|---|
| Tail-recursive loop | 1,000,000 calls |
| Non-tail recursion | 100,000 levels |
| `List.range` | 1,000,000 elements |

In a real browser (Chromium), timings:

| Workload | Time |
|---|---|
| `List.map` over 20,000 elements | 0.4 s |
| `depth(20000)` | 0.3 s |
| 100,000 tail calls | 1.6 s |

Cost:
- About 25-40% slower on call-heavy code: `fib(20)` 285 → 360 ms in Node.
- Same startup.
- A smaller bundle: 1.87 MB → 1.69 MB raw, 410 → 363 KB gzipped.

**Also fixed.** The browser REPL re-ran `main` after every later definition. It
checked whether the session held a `main`, not whether the input defined one.

**Tests.** `scripts/browser-repl-smoke.js` covers:
- `List.map` over 20,000 elements;
- `depth(5000)` non-tail recursion;
- defining a function after `main` (main must not re-run).

The old build fails 5 of these cases.

Still separate: the browser interpreter is slow per call (about 13-25 µs), and
`UUID.v4` needs `crypto.getRandomValues` instead of `/dev/urandom`.
