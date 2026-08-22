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

---

## RESOLVED (2026-08-22) — and the premise was wrong in a useful way

This file's option 1 ("correct the comment, it's the honest cheap fix") assumed
the sentence above it: *"That fix (`e73644aa`, 2026-07-20) did remove the
two-`write()` tear it targeted."* It did not. Not in compiled code.

### `@march_println` was never called

`println` is the POLYMORPHIC prelude wrapper, and a module-level `fn` shadows
the builtin of the same name. `stdlib/prelude.march` had:

```march
fn println(x) do
  print(show(x))
  print("\n")
end
```

so every compiled `println` lowered to two `march_print` calls — two `write(2)`
syscalls with an arbitrary gap between them. The writev was unreachable. This is
checkable without running anything: `@march_println` is DECLARED in all 130
committed `.ll` goldens under `test/native/` and CALLED in zero of them. The
smallest possible program shows it:

```
$ march --compile --emit-llvm --opt 2 simple.march   # println("hello"); println(42)
march_println calls=0   march_print calls=4
```

So the tear this file describes was not a subtle writev-splitting story at all.
It was the ORIGINAL two-`write()` tear, still fully present in compiled code
thirteen months after it was reported fixed, because the fix landed on a
function the compiled backend does not reach. `march_println`'s comment was
wrong twice over: not only was the POSIX claim unfounded, the code carrying it
was dead.

### Reproduction, and what it measured

Four green threads over `MARCH_NUM_SCHEDULERS=8`, each printing a fixed 32-byte
payload 300 times; a line is intact iff it is exactly one of the four payloads.
Torn output has the two signature shapes — two payloads concatenated on one
line, and a stranded empty one — so the total line count stays 1200 while the
INTACT count drops. On darwin 25.5.0 / arm64, load average ~30-60:

| build | torn runs | intact lines (of 1200) |
|---|---|---|
| `origin/main` | 30/30, 58/60 | 756 in the recorded run |
| fixed | 0/60, 0/30 | 1200 |

### The fix

1. `print_line : String -> Unit`, a new builtin bound to the SAME C symbol
   `march_println`, under a name the polymorphic wrapper does not shadow.
   `prelude.march`'s `println` (and `debug`) now call it — one call, one syscall.
2. A `pthread_mutex` held across the `writev` in `march_println`, so the
   atomicity claim also holds across OS threads rather than only against green
   threads on one scheduler thread.
3. The comment rewritten to say what is actually true, including that POSIX does
   not promise what it used to claim.

### Cost, measured — the fix is ~2x FASTER than main

This file said option 2 "needs a benchmark justification nobody currently has".
Here it is. 300,000 lines to a regular file, `--compile --opt 2`, five
interleaved reps A/B/C to control for drift, on a contended box (load 31-37, five
other `main.exe` builds running; reported because it inflates every number).

| config | reps (s) | median |
|---|---|---|
| A = `origin/main` (2x `write`) | 3.03 2.41 2.47 2.24 2.33 | **2.41** |
| B = `print_line`, no lock | 1.43 1.17 1.24 1.20 1.40 | **1.24** |
| C = `print_line` + lock | 1.54 1.19 1.19 1.23 1.36 | **1.23** |

Halving the syscall count roughly halves the wall time, and the lock is free in
a single-threaded print loop. Under CONTENTION (4 tasks x 75,000 lines,
`MARCH_NUM_SCHEDULERS=8`, load 28-35) the lock costs about 5%, at the edge of
this box's noise:

| config | reps (s) | median |
|---|---|---|
| B = no lock | 2.92 2.70 2.26 2.43 2.13 | **2.43** |
| C = lock | 2.61 2.60 2.40 2.33 2.56 | **2.56** |

Net against `main`: faster uncontended, faster contended, and correct.

### What could NOT be verified

The writev-splitting this file reports (17/400 under load, via a `Signal.watch`
handler drained on an idle scheduler thread) was **not reproduced**. With
`print_line` in place but the lock REMOVED, the single `writev` held for **0
torn runs across 280 runs / ~656,000 lines**, all at load ~58:

| payload | schedulers | sink | runs x lines | torn |
|---|---|---|---|---|
| 32 bytes | default | file | 60 x 1200 | 0 |
| 32 bytes | 8 | file | 60 x 1200 | 0 |
| 2 bytes | 12 | file | 80 x 3200 | 0 |
| 2 bytes | 12 | pipe | 80 x 3200 | 0 |

Either the split needs the
signal-drain thread specifically (a different code path from `task_spawn`, and
this repo's own recorded evidence for it stands), or it needs conditions this
box did not produce. The lock is kept on that recorded evidence and because it
measured free, NOT because this work observed it fixing anything.

### Test

`test/native/println_line_atomic.march` + `.expected`, wired into `test/dune`.
Two assertions, because the two halves fail differently:

```
intact 1200
march_println 1 march_print 0
```

The first is the observable symptom and needs concurrency. The second pins the
MECHANISM out of the emitted IR and is fully deterministic — it is the assertion
that would have caught this in 2026-07, and the one that will catch a future
prelude edit that quietly splits the line again.

RED, by file-copy swap of `stdlib/prelude.march` and `runtime/march_runtime.c`
back to `HEAD` (`git show HEAD:<path>`, never `git stash` — shared stash stack)
followed by `dune build --root . @warm-cache`, verified restaged
(`print_line` count 0, `march_stdout_mu` count 0):

```
intact 756
march_println 0 march_print 2
```

GREEN with the fix restored: zero diff.
