# DONE binary-trees: static nullary constructor cells, preemption ticks only for busy schedulers

Done 2026-10-07. Follows `specs/todos/2026-08-04-x86-benchmark-findings.md`
(section 2, binary-trees), which stays open for its other findings.

## Where binary-trees stood

Measured first on an Apple M3 Max (the August numbers were x86, before the
mimalloc default and the `calloc` → malloc change): March 119 ms, OCaml
24.5 ms, Rust 154 ms, all printing the same output. A `sample` profile showed
two causes beyond the allocator itself.

## 1. Every nullary constructor was a heap allocation

`alloc Tree.Leaf()` called `march_alloc(16)` and a later free, for a cell
whose whole content (rc, ctor tag, type id) is a compile-time constant: half
of binary_trees' allocations, and every list's `Nil`.

`Llvm_emit_alloc.emit_alloc_ctor` now emits a nullary constructor of a boxed
type as a pointer to one immortal `internal global` per constructor
(`Llvm_ctx.intern_static_nullary`), exactly as capture-free closures already
are (`intern_static_closure`). rc = `MARCH_RC_IMMORTAL`, so every decrement
path skips it, `march_free` refuses it, and the FBIP `rc == 1` test is false,
so it is never reused or written in place. Same eligibility as the static
closure arm (not in the REPL/JIT, not under hot reload, where a cell in a
patch `.so` would dangle after unload), and never for an actor struct (written
in place) or an actor message type (its tag may be rewritten on migration).

## 2. Idle schedulers preempted the busy one

`march_preempt_request` is one global flag, and the preemption daemon ticked
every scheduler thread. A tick handled by an IDLE scheduler set the shared
flag, so the one busy green thread yielded on every scheduler's tick: 283
yields in a 75 ms run on 14 schedulers (40 with `MARCH_NUM_SCHEDULERS=1`),
and after nearly every yield an idle scheduler stole it, so it ran on a new
core with cold caches and freed its objects across threads (mimalloc's
`mi_free_generic_mt` path).

`march_scheduler` gained `_Atomic int busy`, set around the switch into a
green thread in `sched_loop`. The daemon signals only busy schedulers, and the
tick handler sets the shared flag only when its own scheduler is busy. Yields
in the same run: 283 → 52.

## Result

Same machine, interleaved, minimum of 9 runs, identical output before and
after:

| benchmark | before | after | OCaml | Rust |
|---|---:|---:|---:|---:|
| binary_trees | 120.3 ms | 74.2 ms | 21.9 ms | 151.5 ms |
| list_ops | 39.0 ms | 34.1 ms | 32.5 ms | 5.1 ms |
| list_ops_nested | 45.8 ms | 43.0 ms | | |
| tree_transform | 641 ms | 599 ms | 3931 ms | 5074 ms |

binary_trees is still 3.4× OCaml. What is left, from the profile: a separate
`__drop$Tree` traversal after `check` (which only borrows the tree; OCaml has
no third pass), mimalloc malloc/free, and per-object bookkeeping (the
`live_allocs` counter's thread-local, about 8% in an ablation, and the free
path's provenance check, which is load-bearing: routing frees straight to
`mi_free` crashed).

## Verification

- `test/native/static_nullary_ctor.march` (+ `.expected`, the interpreter's
  output): nullary constructors built, matched (top level and nested),
  rebuilt by FBIP, compared, printed, stored in a `Map` and dropped, with a
  churn loop that must stay flat. IR check: `make` calls `march_alloc` once
  (the non-nullary constructor) and the static cell is emitted.
- Benchmarks above, outputs identical.
- Full suite and ASAN sweep: left to CI (the local runs were stopped by a
  full disk).

## Found along the way

- A nested pattern on a constructor whose name the stdlib also uses
  (`Leaf`, `Node`) takes the wrong arm compiled, with or without this change:
  `specs/todos/2026-10-07-nested-pattern-ctor-name-collision-miscompile.md`.
