# NativeArray.set_int / set_float: FBIP in-place update at unique ownership

Closes the first bullet of
`specs/todos/2026-08-04-compiled-backend-nativearray-set-int-queue-retain-memory.md`
(the `set_int` copy-per-op leak). The `Queue` and `RingBuf` bullets of that
todo are left open — see "Queue: diagnosed, not fixed" below.

## Diagnosis (compiled, `--compile --opt 2`, peak RSS via `/usr/bin/time -l`)

A 2M-op loop whose only per-op heap op is `NativeArray.set_int` on an
8-element array, threaded forward (last-use, RC=1):

| ops   | RSS before | RSS after |
|-------|-----------:|----------:|
| 500k  |      48 MB |    2.6 MB |
| 1M    |      94 MB |    2.6 MB |
| 2M    |     187 MB |    2.6 MB |
| 4M    |     371 MB |    2.6 MB |
| 8M    |     740 MB |    2.6 MB |

Before the fix RSS was perfectly **linear** in ops (~93 bytes/op) — that is a
**true leak** (case (a) in the todo's taxonomy), not an allocator high-water
mark. Root cause: `native_int_arr_set` / `native_float_arr_set`
(`runtime/march_runtime.c`) are passed their array under the **owned/consumed**
convention — they are absent from `borrow.ml`'s `extern_borrow_table`, so
Perceus transfers one reference into the call and emits **no `dec_rc` after
it** (confirmed via `MARCH_DUMP_TXT=perceus`). But the C code only allocated a
fresh backing array, `memcpy`'d, and returned it — it never released the
consumed input. One 8-element array leaked per call.

## Fix

Reuse the backing array **in place when it is uniquely owned** (`rc == 1`, the
same predicate LLVM-generated FBIP `reuse … as …` uses, read as a plain
non-atomic load — safe because a unique owner has no concurrent observer):
O(1), no allocation, no copy → flat RSS. When the array is **shared**
(`rc > 1`) copy-on-write is preserved (allocate, copy, write) and the consumed
reference is released with `march_decrc` — so an aliased array is never
mutated out from under its alias. This is the same FBIP in-place-at-unique-
ownership story March already applies to ADT reuse.

Correctness-critical: the `rc == 1` gate is what makes it safe. It also
excludes interned/immortal arrays (`rc >= MARCH_RC_IMMORTAL`).

## Tests (compiled-only — the interpreter uses a different NativeArray backend)

`test/test_codegen.ml`, group `native_arrays`:
- `…set_int_alias_cow_compiled` — aliases the array (rc>1) and asserts the
  alias reads the ORIGINAL (0), the result reads the mutation (99). In-place
  mutation here would corrupt the alias.
- `…set_int_inplace_churn_compiled` — 2M-op rc==1 churn, asserts the final
  sum (15999964). Would crash / read freed memory / diverge if in-place reuse
  ever freed a still-live array.

Full suite green (compiler 711, eval 256, codegen 546). The stdlib
`MARCH_SANITIZE` adversarial test could not run: ASAN hangs in
`FindDynamicShadowStart` on this macOS build even for a trivial hello-world
(hangs before `main`), an environmental clang/OS issue independent of March —
so it is not a usable check here. Memory-safety evidence instead: correctness
preserved, the alias test, and `march_decrc`'s RC-underflow abort not firing
across 2M+ ops.

## Queue: diagnosed, not fixed (separate root cause)

The todo's `Queue` bullet is **also a true leak** (linear: 33→475 MB over
500k→8M ops), not the allocator high-water the todo speculated. But it is a
**distinct root cause** and is left for a focused follow-up:

- Plain persistent-list cons/uncons churn and a tuple-in-`Option` churn are
  both **flat** (~2.7 MB) — so it is not general List/tuple RC.
- An **inline** two-list ADT push/pop churn is **flat** — so it is not the
  two-list-ADT shape either.
- The leak appears only across the **stdlib `Queue` function boundary**
  (`push_front`/`pop_front`). The post-Perceus TIR of `pop_front`'s hot branch
  allocates a **join-point closure** (`$jp_clo…`, ~32 bytes) and captures it
  into a sibling `$jp_clo` that is `reuse`d-and-`dec_rc`'d; the captured
  closure FV appears not to be reclaimed. 67 MB / 2M ≈ 33 bytes/op ≈ exactly
  one leaked closure box per op.

That is a join-point-closure RC / materialization issue in the nested-match
lowering, high blast radius, and unrelated to the `set_int` C-runtime bug — so
it was not folded into this change.
