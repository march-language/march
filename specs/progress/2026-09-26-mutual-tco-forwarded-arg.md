# TCO loops defer the release of a forwarded argument to the loop's exit

Closes [[2026-09-20-mutual-tco-safety]]'s open half (option 2 of the todo this file
was, filed 2026-09-20 as "Mutual TCO frees a forwarded argument one iteration early
(or leaks it)", P1, downgraded to P3 on 2026-09-22 once option 1 had removed the
use-after-free). Covers the self-TCO mirror of the same problem too, which the todo
said option 2 should.

## The problem

A tail call that forwards an owned value to a BORROWED parameter is followed by a
release of that value. Perceus writes it as

```
let t = inspect(x, rest, why) in dec_rc why; t      -- mutual, ELet shape
ESeq(last_len(rest, $t), dec_rc $t)                 -- self, ESeq shape
```

Under real recursion the release runs after the nested call returns. A flattened
loop has no such point, and both ways the back edge used to handle it were wrong:

- **run it on the back edge** (the mutual arms before 2026-09-20): frees the value one
  instruction before the next iteration reads it -- `refused: no-y; refused: no-y`,
  a heap-use-after-free in `march_string_eq` under ASAN;
- **skip it** (the self arms since eafbd71a): nothing ever releases it -- one value
  leaked per iteration.

Option 1 (2026-09-20) stopped flattening such a MUTUAL group, which was correct and
leak-free but cost the loop, and left the self-TCO leak alone.

What that meant on `origin/main` (1877afc22), both measured before the fix:

- **stack overflow.** The todo's own pair (`take_next`/`inspect`) at depth 3,000,000,
  and the new fixture's pair at 1,000,000, die compiled with
  `march: fatal SIGBUS ... fault in its stack guard page (overflow)`, exit 138. The
  interpreter runs them fine.
- **leak.** A self-recursive `last_len(xs, why)` handing `"w" ++ x` to its borrowed
  `why` on every element: `live_allocs()` grew by 100,003 over a 100,000-element walk
  (0 is expected; the list itself is freed). LeakSanitizer (Linux container, ASAN
  build) on `test/native/tco_fresh_arg_decrc.march`, which is that shape: 936 bytes in
  36 allocations, 7 of them `march_string_join` results from `str_to_int`.

## The fix: a pending-drop list

The loop keeps recursion's ownership semantics without its stack. A loop function
(self-TCO `emit_fn` or a mutual group's `__mutco_` dispatcher) that has a back edge
releasing a forwarded, non-dup-bound argument gets one extra `alloca ptr`, set to NULL
in the entry block. On such a back edge the release is not emitted and not skipped:

```
%old = load ptr, ptr %tco_defer.addr
%new = call ptr @march_tco_defer_push(ptr %old, ptr @march_decrc_local, ptr %why)
store ptr %new, ptr %tco_defer.addr
```

and just before every `ret` of the loop function (after the result is computed, and
the result owns its own reference):

```
call void @march_tco_defer_drain(ptr %buf)   ; runs every release, newest first, frees the list
```

That is exactly when, and in exactly the order, the frames of the equivalent recursion
would have run the releases. The list stores (release fn, value) pairs because the
release is not always a DecRC: `EDecRC` -> `march_decrc_local`, `EAtomicDecRC` ->
`march_decrc`, `EFree` -> `march_free`, a deep drop -> its `__drop$T`, all
`void (ptr)`. The no-op cases of the ops' own arms are kept (a non-pointer value; a
top-level function or builtin name that is not a local).

- `runtime/march_runtime.c` / `.h`: `march_tco_defer_push` (malloc'd growable array,
  starts at 16, doubles; plain C memory, invisible to `live_allocs`) and
  `march_tco_defer_drain` (accepts NULL).
- `lib/tir/llvm_tco.ml`: `is_release_op`, `forwarded_args` (the one definition the
  analyses and the arms share), `back_edge_forwarded_op` with its two instances
  (`back_edge_drops_forwarded_arg`, `back_edge_incs_forwarded_arg`),
  `has_group_back_edge` (the old `has_unsafe_group_back_edge` with the predicate as a
  parameter), `needs_defer_list` (decides the slot up front, since it must be in the
  entry block), `emit_defer_slot_init`, `emit_defer_drain`. `group_back_edges_safe`
  now refuses only a group whose back edge INCREMENTS a forwarded argument, which
  Perceus does not emit; a release no longer refuses the group. The mutual emitter
  sets `tco_dup_bound` per member (the arms did not consult it before) and drains
  before each case's `ret`.
- `lib/tir/llvm_emit_tcoarm.ml`: the four arms' duplicated chain loops are one
  `emit_back_edge_chain`; `emit_defer_release` emits the push. An op on a
  non-forwarded target or on a dup-bound argument is still emitted as before. An
  increment of a forwarded argument is still skipped on a self back edge (unchanged).
- `lib/tir/llvm_toplevel.ml`: `emit_fn` allocates the slot for a self-TCO function
  that needs it and drains before its `ret`.
- `lib/tir/llvm_builtins.ml`: the two declares.

If the arm ever meets a release the pre-scan did not see, it fails loudly
(`internal: TCO back edge ... has no pending-drop list`) rather than falling back to
either wrong answer.

## What it costs

A function gets the slot, the drain, and a push per iteration only if it has the shape;
everything else emits the same IR as before plus two `declare` lines. Across `bench/`
(51 programs), `--emit-llvm` finds a push in exactly one: `DataFrame.eval_agg`, reached
from `dataframe_bench` (a self back edge that was leaking). `list_ops`, `tree_transform`
and the rest have none. The values are held until the loop returns rather than freed
as they go, which is what the recursion did too (its frames held them), and strictly
better than the leak the self shape had.

## Tests

- `test/native/mutual_tco_deferred_drop.march` (+ `.expected`, the interpreter's
  output) with its golden `test/dune` rule and an IR-shape rule
  (`mutual_tco_deferred_drop_llvm_check`: >=1 `@__mutco_` definition, >=2 pushes, >=2
  drains, so it cannot pass after the inliner folds the pair or the group is refused).
  The inputs ALTERNATE between each function's two branches (`no-1`, `ok-2`, ...),
  since a two-branch function checked with all-one-branch input proves nothing. It
  walks the self pair 200,000 steps and the mutual pair 1,000,000 steps, and asserts
  `live_allocs` held under 1000 after each.
  - RED on 1877afc22: `self: ... under 1000: false`, then SIGBUS stack overflow in the
    mutual walk, exit 138.
  - GREEN: identical to the interpreter, exit 0.
- `test_codegen.ml`, `mutual_tco_codegen`: B7
  (`test_mutual_tco_borrowed_arg_decref_on_live_path`) flipped back, as the todo said
  it would: the pair is flattened, `prefix`'s release is a
  `march_tco_defer_push(..., @march_decrc_local, ...)` on the live back-edge path (no
  block label between it and `br label %mutual_loop`), and the dispatcher drains. New
  `test_tco_self_fresh_arg_release_deferred`: `tco_fresh_arg_decrc`'s `str_to_int` is
  still a loop and now pushes and drains.
- `test/native/mutual_tco_forwarded_arg.march` (the UAF fixture) is flattened again and
  still prints `refused: no-x; refused: no-y`.
- ASAN (Linux `march-amdr-repro` container, `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`,
  base and fix built side by side): with the fix, no AddressSanitizer error on either
  fixture, a 3,000,000-step variant of the todo's repro, the self-leak repro, or B7's
  program. `tco_fresh_arg_decrc` goes from 936
  bytes / 36 allocations leaked to 754 / 29: the seven `march_string_join` strings are
  gone. The 754 bytes left are `march_string_lit` allocations in `str_to_int`,
  present identically on 1877afc22 and not investigated here.
- `test/refine_audit/corpus.baseline`: the two `native_mutual_tco_deferred_drop` lines.
- TIR snapshots: unchanged (45 cases; this is an LLVM-emission change).

## Benchmarks (compiled, `--opt 2`, A/B vs a compiler built from 1877afc22, alternating, one warm-up each)

| benchmark | 1877afc22 (ms, 5 runs) | this change (ms, 5 runs) |
|-----------|------------------------|--------------------------|
| `bench/list_ops.march` | 79, 75, 76, 76, 79 | 79, 79, 78, 75, 78 |
| `bench/tree_transform.march` | 669, 658, 668, 669, 654 | 663, 656, 667, 660, 669 |
| `bench/dataframe_bench.march` (3 runs) | 48, 48, 48 | 49, 48, 48 |

Load average ~4.5 (other sessions on the box), so the resolution is a few ms; the pairs
overlap entirely. Outputs are identical except `dataframe_bench`'s self-reported
per-step timings. `list_ops` and `tree_transform` contain no deferral site, so their
emitted code differs only by the two preamble declares; `dataframe_bench` is the one
bench program with a push (`DataFrame.eval_agg`) and shows no measurable cost.

Unit-test RED: with this branch's `test_codegen.ml` built against 1877afc22,
`mutual_tco_codegen` 5 (B7, "the group is flattened") and 7 (the self deferral test)
fail; both pass here. The only other failures a full `scripts/run-tests.sh` showed
were the three `llvm_builtins_preamble_golden` byte-diffs, which the two new declares
change by design; the golden blob in `test_codegen.ml` gains those two lines (and the
WASM runtime gains matching no-op definitions, its RC ops being no-ops already).
