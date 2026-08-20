# CLOSED: `NativeArray.set_int` / `Queue` / `RingBuf` retention (all three bullets)

Closes `specs/todos/2026-08-04-compiled-backend-nativearray-set-int-queue-retain-memory.md`
(this file is that item, moved). Filed 2026-08-04 against the steady-state
flat-RSS demo; **re-verified 2026-08-20 and closed — all three bullets are
resolved.** Two had been fixed since filing and the file had gone stale; the
third was never a leak.

## Bullet 1 — `NativeArray.set_int` copy-on-write not reclaimed: FIXED

`native_int_arr_set` in `runtime/march_runtime.c` now takes an in-place FBIP
path when it is the sole owner, instead of always copying:

```c
void *native_int_arr_set(void *arr, int64_t i, int64_t val) {
    if (IS_HEAP_PTR(arr) && ((march_hdr *)arr)->rc == 1) {
        *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8) = val;
        return arr;
    }
    ...
    march_decrc(arr);      /* and the copy path now releases the old array */
    return new_arr;
}
```

Landed in `e32865b6` — *"fix: NativeArray.set_int/set_float FBIP in-place
update at rc==1 (stops per-op leak)"* (PR #186). Exactly the "FBIP in-place
reuse when RC=1" resolution the bullet listed as one of its open options.

## Bullet 3 — `RingBuf` has no compiled backend: FIXED

`RingBuf` has one. `ring_buf_make` / `push` / `pop` / … are defined in
`runtime/march_runtime.c` (from ~line 8231, *"Compiled backend for
stdlib/ring_buf.march"*) and declared in `lib/tir/llvm_builtins.ml` (~line 780).
The claimed `Undefined symbols: _ring_buf_make` link failure no longer occurs.

## Bullet 2 — persistent `Queue` retention: NOT A LEAK

This was the one bullet never verified. Measured 2026-08-20, compiled
(`--opt 2`), depth-1 `push_back` + `pop_front` per op with the queue threaded
forward, signal = `live_allocs()` (net live March objects) rather than RSS:

| ops | `live_allocs()` delta |
|---|---|
| 200,000 | **4** |
| 400,000 | **6** |

Flat, not linear — doubling the op count does not double the live set. There is
**no true leak**; the original ~38 MB figure was allocator high-water / page
retention, which is exactly the alternative the bullet itself hedged on
("possibly … allocator page retention rather than a true leak — RSS is
bounded/sub-linear in ops, not monotonically linear"). RSS was the wrong
instrument; the same lesson that retired RSS from the leak probes in
`test/native/` applies here.

## Why this mattered

The file was materially misleading to release review: two of its three bullets
described defects that had already been fixed, one of them nearly four months
earlier, in a directory whose entire purpose is to be the canonical record of
what is still open.
