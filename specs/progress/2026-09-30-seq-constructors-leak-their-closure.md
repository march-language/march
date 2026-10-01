# `Seq` constructors and combinators no longer leak per use (compiled)

**Landed 2026-09-30.** Closes the todo of the same name (filed 2026-09-29 while
fixing `2026-09-30-process-spawn-lines-leaks-and-wrong-payload.md`).

## The defect

`--compile --opt 2`, `live_allocs()` delta per iteration of a one-element
sequence built and drained (origin/main):

| body | per iteration |
|---|---|
| `Seq.count(Seq.from_list(["a"]))` | 3 |
| `Seq.count(Seq.from_string_lines("a\n"))` | 5 |
| `Seq.count(Seq.map(Seq.from_list([1,2,3]), f))` | 5 |
| `Seq.count(Seq.filter(Seq.from_list([1,2,3]), p))` | 5 |

The todo suspected the closure, the `Seq` cell or the captured list. It was
four separate defects, none of them in `stdlib/seq.march`'s shape.

1. **A forwarded capture was never released** (`lib/tir/drop.ml`,
   `rewrite_apply_clo_drop`). `from_list`'s lambda `fn(acc, f) -> go(xs, acc, f)`
   tail-calls through `go` and `xs`, both captures. The pass releases a
   capture on the path where the environment died owning it, but declined any
   capture the tail still uses (the call may recurse, so no work may follow it).
   Perceus had already `inc_rc`'d each such capture just before the call, so the
   extra reference keeps the value alive across the call and the environment's
   own reference can be dropped at the tail. The release is now emitted when
   the run of `inc_rc c` immediately before the tail covers every occurrence of
   `c` in the call. Anything else keeps the old conservative leak.
2. **FBIP un-made the immortal static closure** (`lib/tir/perceus_fbip.ml`).
   `Seq.count`'s `fn(n, _) -> n + 1` captures nothing, so `llvm_emit`
   materialises it as one immortal global and its apply function never releases
   `$clo`. But the dying `Seq` cell is a 1-field cell, and `alloc $Clo_f(apply)`
   is a 1-argument alloc, so FBIP turned it into `reuse seq as $Clo_f(apply)`:
   a real refcounted cell that nothing balances. `try_fbip_sink` and `fbip_expr`
   no longer reuse into a capture-free closure struct.
3. **`closure_escapes` was blind to `EReuse`** (`lib/tir/borrow.ml`).
   `Drop.owning_apply_fns` runs after FBIP. `Seq.map`/`filter`/`concat` store the
   closure they build with `reuse seq as Seq(clo)`, which read as "does not
   escape", so the closure type was declined by the owning-environment gate and
   its captures were never released. `EReuse` and `EAllocHole` arguments now count
   as storage. The only other caller, `owned_in`, runs before FBIP and never sees
   an `EReuse`, so borrow inference is unchanged.
4. **A dead join-point closure leaked its dups** (`lib/tir/drop.ml`,
   `dead_clo_pair`). `from_string_lines` strips a trailing empty line with a
   `rest -> Cons(h, rest)` fall-through. Lowering allocates the fall-through
   join-point closure at the head of the `Nil` arm, which never calls it, and
   drops it with a shallow release: the `inc_rc h` taken for it was never
   balanced, and the scrutinee the closure had been handed was never released
   (so the scrutinee's own drop was also suppressed). `let c = (inc_rc x;)*
   alloc $Clo_f(..) in dec_rc c; rest` with `c` dead in `rest` is now dropped
   outright; a dup'd capture loses its dup, and a capture handed over without a
   dup is released only when it is a local bound to the result of a call or an
   allocation (an owned value). A first version released ANY moved-in capture,
   which over-released a borrowed one: `two-node[cert_expired]` aborted with
   `tcache_thread_shutdown(): unaligned tcache chunk detected` on Linux (6 of 6
   runs; 0 of 6 on origin/main, 6 of 6 clean with this restriction). Reproduced with no `Seq` involved (`strip` in the probe).

## Evidence

`test/native/seq_constructor_leak_probe.march` (new): `from_list`+`count`,
`from_string_lines`+`count`, `from_list`+`fold`, `map`+`count`, `filter`+`count`,
`concat`+`count`, and the `strip` fall-through. origin/main: every leg
`flat: false`. Now: every leg `flat: true` (delta 1 over 40 iterations, the
`println` string).

`Process.run_stream` is now a leg of `test/native/process_handle_leak_probe.march`
(`flat: false` on origin/main, `flat: true` now), next to the direct
`process_spawn_lines` leg, which is kept to isolate the builtin.

## Still open

A *capturing* closure whose last reference is released at an outer site (not
inside its own apply function) is still shallow-freed and leaks its captures:
`Seq.count(Seq.map(Seq.from_list(xs), fn x -> x + i))` leaks one object per call,
and so does `Seq.fold(Seq.filter(Seq.map(...)), ...)` where the inner combinator's
environment is a dynamic closure. This is item 3 of
`specs/todos/2026-09-06-closure-capture-release-widening.md` (the runtime
drop-table attempt was a use-after-free); nothing here changes it.
