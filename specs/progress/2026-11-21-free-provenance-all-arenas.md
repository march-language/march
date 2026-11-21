# Free's provenance test knows every mimalloc arena (done 2026-11-21)

Reported from Ur: a 500,000-citizen city on a 120×88 island holds about 4.5 GB. Its
simulation worker spent ~23% of its samples in `march_free_any_slow` →
`march_mi_owns_slow` → `mi_is_in_heap_region` (20% self).

## Cause

`march_free_any` (`runtime/march_alloc.h`) routes a pointer to `mi_free` or libc `free`
by provenance. Its inline fast path compares against the bounds of mimalloc's FIRST arena
only (mimalloc reserves 1 GiB arenas). Every object in arena 2 and later took the
out-of-line `mi_is_in_heap_region`: an arena-table walk plus a segment-map lookup.

## Fix

`march_mi_owns_slow` keeps a table of up to 32 more arena ranges, learnt lazily the way the
first one is (a slot claimed with `fetch_add`, bounds stored relaxed; a half-written slot
reads as an empty range, so a reader only falls through to the full test). It checks the
table before `mi_is_in_heap_region`, and after a yes from that call records the arena that
holds the pointer. Arenas are never unmapped while the process runs, so entries never go
stale. A libc pointer pays the table scan (at most 32 compares) before the full test.

## Measured

Ur metro, 500,000 citizens, 120×88: see the Ur `perf/large-island` notes for frame
times before and after.
