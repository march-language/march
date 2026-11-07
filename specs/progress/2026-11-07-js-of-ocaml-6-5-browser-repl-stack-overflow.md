# js_of_ocaml 6.5: browser REPL stack overflow fixed, `< 6.5` pin lifted (2026-11-07)

Logged 2026-11-02 (`specs/todos/`, P3): built with js_of_ocaml 6.5.0, the in-browser
REPL (`docs/assets/march.js`) failed the `browser-repl` smoke case

    List.length(List.map(List.range(0, 20000), fn x -> x + 1))
    expected "20000\n", got: RangeError: Maximum call stack size exceeded

so `dune-project` pinned `js_of_ocaml (< 6.5)`.

## Reproduction

A separate opam switch (`march-jsoo65`, created with `--no-switch` so the shared `march`
switch and the global default were never touched) with OCaml 5.5.1 and js_of_ocaml
6.5.0. Bundles built from it with `dune build --profile release --build-dir ...`
`js/march_browser.bc.js js/march_browser_compile.bc.js`, dropped into an otherwise
normal `scripts/build-browser-repl.sh --out` tree: the smoke test failed exactly that
case (2 assertions, output and error). The same tree built with 6.4.1: 53 cases pass.

## Cause

The stack trace (a `--pretty --debug-info` 6.5.0 build, every `catch` patched to keep
the first `RangeError`'s stack) was the same four frames over and over:
`apply`'s join continuations `a` and `c` (`lib/eval/eval.ml`, the `VClosure` arm),
the `EApp` continuation after `apply` returns (`march_stack_pop (); v`), and
`Fun.protect`'s continuation. That is the RETURN path of the 20000-deep `List.map`, not
the call path.

Under `--effects=cps` js_of_ocaml keeps the evaluator's recursion in heap continuations,
but it resets the JS stack only at a CPS call (`caml_*trampoline_cps_call*`), which
counts down `caml_stack_depth` and, past 40, returns to the trampoline. Calling a
continuation (`cont(v)`) is a plain JS call. The return path of a deep non-tail
recursion is therefore a chain of continuation calls, and it only gets bounced if
some CPS call sits on it.

With 6.4.1 one did: `Fun.protect`'s `finally ()` call (`fun.ml:35`, around every March
closure body) was compiled as `caml_exact_trampoline_cps_call`. With 6.5.0 ("specialize
calls to known functions before the CPS transformation", ocsigen/js_of_ocaml#2458) the
call is resolved to the closures it can reach, none of which needs CPS, so it became a
direct `finally_no_exn()` and nothing on the return path checked the depth any more.
It was never a guarantee, just a call that happened to be unknown. (#2441, "CPS only
for functions that may run below a handler", applies to `--effects=double-translation`
only, not to the `cps` mode march.js uses; wrapping the entry points in an effect
handler was tried and changed nothing.)

## Fix

- `Eval_prim.call_return_hook : (unit -> unit) ref` (re-exported as
  `Eval.call_return_hook`), a no-op by default, called by `apply` after every March
  closure body returns. Natively it is one indirect call to a no-op.
- `js/march_browser.ml` sets it to `bounce`, a function that contains `Effect.perform`
  behind a guard read from a JS global no page sets. A function with an effect primitive
  is CPS, and so is every call to it, so the hook call in `apply` is depth-checked on
  every return. The effect is never performed.
- `dune-project` / `march.opam`: `js_of_ocaml (>= 5.0)`, pin removed.

## Verified

Built locally with js_of_ocaml 6.4.1 (`scripts/build-browser-repl.sh --out`) and 6.5.0
(the two bundles from the `march-jsoo65` switch, the rest of the tree from the 6.4.1
build):

| check | 6.4.1 | 6.5.0 |
|---|---|---|
| `scripts/browser-repl-smoke.js` | 53 pass | 53 pass (2 failures before the fix) |
| `scripts/browser-repl-doc-sweep.js` | 3006 clean, 13 expected | same |
| `scripts/check-doc-try-it.js docs/docs/stdlib` | 1491 examples pass | same |
| `List.map` over 100,000 / `depth(100000)` / 1,000,000 tail calls | pass | pass |
| `fib(22)`, median of 5 (Node 22) | 913 ms before, 879 ms after | 699 ms after |

The regression test is the existing smoke case (red on 6.5.0 before this change, green
after); CI's `browser-repl` job runs it on whatever js_of_ocaml a fresh switch resolves,
which with the pin gone is 6.5.x.
