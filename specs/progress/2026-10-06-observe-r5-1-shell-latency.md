# Observe R5.1: what a warm shell input costs

**Date:** 2026-10-06
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R5.1.
**Feeds:** R6's latency gate (design §6.9: p50 ≤ 300 ms, p95 ≤ 600 ms).

## Method

The local REPL is the closest existing thing to R6's warm compiler session:
it keeps the stdlib's typecheck environment and lowered program in memory
and compiles each input as a fragment `.so` (`lib/jit/repl_jit.ml`, clang
backend). Twenty inputs (arithmetic, `let`s, `List.map` / `filter` /
`fold_left` / `zip` with lambdas, a record, a map, string splitting and
joining, `to_string` of lists) were run through `march repl` with
`MARCH_JIT_BACKEND=clang MARCH_JIT_PROFILE=1`. The same compiler (main at
`8fb90417d`) ran on the macOS dev box (load 8) and in the Linux arm64
container (`march-amdr-repro`).

The plan named the conduit test app as the mid-size project. It no longer
parses with the current compiler (an unrelated repository, not changed
here). Per-input cost depends on the input, not the project, once the
environment is warm; project size moves only the one-time attach cost.

## Results (ms per input, p50 / p95)

| Phase | macOS | Linux |
|---|---|---|
| typecheck | 0.0 / 0.0 | 0.0 / 0.1 |
| lower + mono + opt | 5.7 / 14.6 | 7.2 / 15.9 |
| emit IR | 3.0 / 3.7 | 2.8 / 4.0 |
| clang | 83.3 / 87.7 | 26.5 / 28.7 |
| dlopen | 162.4 / 228.4 | 0.1 / 0.1 |
| **compile + load** | **~255 / ~305** | **~37 / ~49** |

Where the macOS `dlopen` time goes: a freshly written trivial C dylib
(one function) takes 136-240 ms to `dlopen` on this Mac and 0.02 ms on
Linux. Re-opening a file already seen takes 0.2-0.4 ms, and a byte-identical
copy under a new name pays the full cost again. So it is macOS checking each
new binary file (the files carry `com.apple.provenance`), not March's symbol
binding, and every new fragment pays it.

## What this means for R6

- **Linux nodes**, where production runs, leave ~250 ms of the 300 ms
  budget for the round trip and the node's side. The gate is comfortably
  reachable, and could be tightened once R6 measures the real path.
- **A macOS node** (a developer's own machine) pays ~150 ms per input in
  `dlopen` alone. The target still holds at p50 but with little room. The
  R6 gate runs against a Linux node; a macOS node's numbers are recorded
  beside it, not gated.
- **clang dominates the compile** on both platforms (80-90% of it). The
  rest of the pipeline is ~10 ms when warm. If R6 needs more room, `-O0`
  for fragments and a persistent clang process are the levers, not the
  front end.

## Found along the way

A REPL input that calls a function with too few arguments
(`let g = List.map([1, 2])`) segfaults the REPL on Linux; macOS reports
`arity mismatch` and continues. Filed:
[`todos/2026-10-06-repl-under-applied-call-segfaults-linux.md`](../todos/2026-10-06-repl-under-applied-call-segfaults-linux.md).
