`[P2]` **The REPL segfaults on Linux when an input calls a function with too few arguments.**

Found during observe R5.1 ([progress](../progress/2026-10-06-observe-r5-1-shell-latency.md)),
2026-10-06, main at `8fb90417d`, Linux arm64 (`march-amdr-repro` container),
`MARCH_JIT_BACKEND=clang`:

```
let g = List.map([1, 2])          -- SIGSEGV, the REPL process dies
let h = Map.from_list([("a", 1)]) -- the same (from_list also takes a comparator)
let f = fn x -> x + 1             -- fine
```

The same inputs on macOS print `runtime error: arity mismatch: expected 2
args, got 1` and the session continues. The typechecker accepts the input
(a partial application has a function type). So the compiled fragment
reaches a call with the wrong arity, and only macOS turns that into a
recoverable error.

Matters beyond the REPL: R6's shell compiles inputs the same way, and an
input that crashes a fragment must never take the node down. Reproduce with
`printf 'let g = List.map([1, 2])\n1 + 1\n' | march repl` on Linux, then
compare the emitted fragment IR with macOS before assuming a platform
difference in the runtime.
