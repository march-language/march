# A main-less compile emitted the whole stdlib

**Date:** 2026-10-04
**Found by:** `scripts/compile-time-bench.sh` (branch `bench/compile-time-harness`),
compiling `examples/topology_app/src/topology_app.march` without its
`--topology .forge/topology.json` digest.
**Open sibling:** [`todos/2026-10-04-field-dyn-on-int-typed-operand.md`](../todos/2026-10-04-field-dyn-on-int-typed-operand.md)
(the invalid IR seen in the same compile).

## Symptom

`llvm-emit` took ~153 s for the topology app without its digest, vs ~21 s with
it. A module with no `main` gives DCE no roots, and `Dce.root_names` fails open
for codegen: it keeps every function. That means the whole prepended stdlib.
Measured on `f2088b568`:

| input | definitions | IR | llvm-emit + clang |
|---|---|---|---|
| `mod NoMain do fn f(x : Int) : Int do x + 1 end end` | 7,938 | 45 MB | 6.5 min (load avg ~120) |
| topology_app, no digest | 8,265 | 47 MB | 85-300 s llvm-emit, by load |

The same fail-open was already a known trap for the `--cap-strict` ceiling,
which roots "the functions this file declares" instead
(`2026-09-18-cap-ceiling-rooted-stdlib-namesakes.md`).

## Fix

`bin/main.ml`: when the lowered module has no roots of its own
(`Dce.root_names ~fail_open:false` is empty), the driver passes the file's own
functions to `Contract_pipeline.run ~extra_roots`, which keeps them as DCE roots
(`tm_exports`). The predicate is the ceiling's, hoisted to top level as
`is_user_tir_fn` (and `tir_fn_stem`) so the two cannot drift apart. Skipped for
`--compile-so`, `--hot-reload`, JS and the WASM-island target, whose roots are
symbols a loader looks up. Also skipped when the file declares nothing, which
fails open as before.

After: the one-liner emits 2 definitions and compiles in ~10 s, most of it
clang on the runtime. The topology app emits 1,205 definitions (8.2 MB), and
`llvm-emit` takes ~7 s. Both binaries link and run (exit 0, since nothing calls
into them).

## Test

`test/native/mainless_prunes_stdlib.march` plus the `mainless_prunes_stdlib`
rules in `test/dune`: `--emit-llvm` must define `@helper` and `@shout` and
emit fewer than 300 definitions. It emits 4 now; the pre-fix compiler emits
~7,900 for the same shape.
