# `march_println`'s single-`writev` line atomicity does not hold across threads

Filed 2026-08-21, found while root-causing
`specs/progress/2026-08-21-signal-watch-output-ordering-flake.md`.

## The claim

`march_println` (`runtime/march_runtime.c`) emits payload and newline in one
`writev(2)` specifically to make a line atomic, and says so:

> Emit the payload AND its trailing newline in a single writev(2) syscall so
> the whole line is atomic against concurrent green threads. […] A single
> vectored write to a regular file/pipe is atomic (POSIX).

That fix (`e73644aa`, 2026-07-20) did remove the two-`write()` tear it targeted.

## The claim is not true on macOS

With two OS threads printing concurrently (a `Signal.watch` handler drained on
an idle scheduler thread while main's green thread printed), lines tore anyway,
at roughly 4% of runs under load — measured 17/400 with both shapes observed:

```
after raisecaught usr2
caught usr2after raise
```

The tear always falls **between the two iovecs** — one thread's `iov[0]` lands,
the other thread's whole line lands, then the first thread's `iov[1]` newline —
so the kernel is splitting the vectored write rather than issuing it atomically.
Each individual message's bytes stayed contiguous in every observed case, which
is why substring matching still works and only line-anchored matching breaks.

Reproduced on darwin 25.5.0 (arm64), to both a regular file (dune
`with-stdout-to`) and a pipe (`popen`).

## Why it is filed rather than fixed

Nothing currently depends on cross-thread line atomicity now that
`native_signal_watch` is pinned to one scheduler, so this is latent rather than
active. But the comment asserts a guarantee the platform does not provide, and
the next person to write a multi-threaded golden will trust it.

## Options

1. Correct the comment to say the guarantee holds only against concurrent
   *green threads on one scheduler thread*, not across OS threads. Cheapest,
   and honest.
2. Serialise `march_println` on a mutex. Real atomicity, at the cost of a lock
   on every line of output — measure against `bench/` before considering it.
3. Leave the code alone and rely on callers not interleaving. Requires at least
   option 1's comment fix anyway.

Option 1 is almost certainly right on its own; option 2 needs a benchmark
justification nobody currently has.

## Not to be confused with

The ordering half of the signal_watch flake, which was a genuine
scheduler-concurrency issue and is fixed. This item is only about the tearing,
and only about the accuracy of the atomicity claim.
