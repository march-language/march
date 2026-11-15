# A consuming match retains a shared cell's fields before releasing it (done 2026-11-13)

march-language/march#1266. A `List` captured by a `task_spawn` closure and
still walked by the spawning thread crashed the compiled program (SIGSEGV,
SIGBUS, SIGABRT); the issue's reducer died in 20 of 20 runs on 8adaee0a8
when the spawner read the list after the spawn, 0 of 20 when before.
Found in Strata's chunk streamer.

## Cause

Not atomicity: compiled refcount ops are atomic (the inline fast path in
`lib/tir/llvm_rc_inline.ml`, and `main` runs on a scheduler worker).
After the spawn both threads own a reference to `items` (`inc_rc items`
before `alloc $Clo...`), and both destructure it with a consuming match:
the task in `walk`, the spawner in `List.length_onto...$own0`. For such a
branch (`dec_rc scrut` first, heap fields bound) `lib/tir/llvm_case.ml`
emitted

    freed = march_decrc_freed(cell)
    if !freed: march_incrc(field_i) ...   ; shared path

i.e. it released the cell and only then took its own references to the
fields. On one thread that is fine. Across two: A decrements 2 -> 1 and
takes the shared path; before A's increments, B decrements 1 -> 0, takes
the unique path (fields pass to B without an increment), walks on and frees
the tail; A's `march_incrc(tail)` then writes freed memory, and A walks it.

## Fix

The branch now tests the count first (`load atomic monotonic`, `rc == 1`):
unique keeps the old path (release frees the shell, fields pass to the
binders). Otherwise it increments the fields while the cell still keeps
them alive, then releases the cell; if that release frees it after all (the
other holder let go in between) the cell's references to the fields are
also ours, so one of each is released (none frees: we hold the other), plus
the erased-slot Float boxes the freed cell owned.

## Tests

`test/native/task_shared_list_capture.march` (15000 reps of 8 spawns):
21 of 30 runs crashed before, 0 of 100 after. The issue's program: 0 of 50
after (VARIANT 0).

## Cost

The extra count test runs on every consuming match. macOS arm64,
`/usr/bin/time -l`, `--opt 2`, three runs each: `bench/tree_transform`
6.99e9 -> 7.75e9 instructions (+11%), user 0.53-0.55 -> 0.56-0.59 s;
`bench/binary_trees` 7.67e8 -> 8.14e8 (+6%); `bench/list_ops` 3.70e8 ->
3.75e8 (+1.5%). Cheaper would be a dedicated "free a unique shell" runtime
entry with its own inline twin, so the unique path skips the twin's second
heap check and atomic RMW; not done here.
