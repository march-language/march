`[P3]` js_of_ocaml 6.5.0 overflows the JS stack in the in-browser REPL; pinned `< 6.5`

**Seen** 2026-11-02 on PR #1054 (CI run 41486762534, job `browser-repl`). That PR
changed the opam cache key, so CI built a fresh switch for the first time since
js_of_ocaml 6.5.0 came out (2026-10-22); the macOS log of the same run shows
`installed js_of_ocaml.6.5.0`. `scripts/browser-repl-smoke.js` then failed one
pinned case, under the same Node (v22.23.4) that passes on main:

    List.length(List.map(List.range(0, 20000), fn x -> x + 1))
    expected "20000\n", got: RangeError: Maximum call stack size exceeded

Main's cached switch, and a local 6.3.2, pass. The 6.5.0 changelog has
effect-handling changes ("specialize calls to known functions before the CPS
transformation", #2458; CPS only for functions that may run under a handler,
#2441) that plausibly change the stack depth of the interpreter's non-tail
recursion.

`dune-project` now pins `js_of_ocaml (< 6.5)`. To lift it: build the browser
REPL with 6.5.x (`scripts/build-browser-repl.sh`), run the smoke test, and
either fix the depth (a larger stack for the interpreter's recursion, or
whatever `--effects` mode we build with) or report it upstream.
