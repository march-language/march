# `MARCH_SANITIZE=thread` on macOS reports races in `march_decrc` across green threads

Logged 2026-10-07 while fixing the macOS ASAN hang
(specs/progress/2026-10-07-macos-asan-hang.md). Until then TSAN never got past
startup on macOS 26 (Apple clang 17's TSAN runtime segfaults); with the driver now
falling back to Homebrew LLVM 22, it runs.

`test/native/hof_spec_closures.march` is clean. `actor_counter.march` (11 reports) and
`nativearray_builtin_borrow_leak_probe.march` (53) abort with "data race" between a
plain read in `march_decrc` (runtime/march_runtime.c ~606) on one scheduler thread and
the atomic write at ~610 on another, under `actor_green_thread` / `proc_trampoline`.

The scheduler already has TSAN fiber annotations (`MARCH_TSAN_SWITCH_TO_*`,
runtime/march_scheduler.c), so this is not obviously an annotation artifact. The read at
~606 is the immortal-cell check, a plain `((march_hdr *)p)->rc >= MARCH_RC_IMMORTAL`
load of a word other threads update with `atomic_fetch_sub`. That is a C11 data race
(benign in practice: the load only compares against the immortal threshold), and TSAN is right to flag it.
Likely fix: make it an `atomic_load_explicit(..., memory_order_relaxed)` (and audit the
same pattern in `march_incrc` and the other rc readers), then re-run the three programs
under `MARCH_SANITIZE=thread` on macOS to see what is left.
