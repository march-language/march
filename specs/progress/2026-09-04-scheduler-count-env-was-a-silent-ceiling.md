# `MARCH_NUM_SCHEDULERS` was a silent ceiling, not a setting

**Status:** filed and **shipped 2026-09-04.** Found while root-causing a voxel
engine's meshing throughput (the reporter's write-up is item **G71**; G72 and
G73 there are independent and deliberately untouched by this change).

## The bug

`runtime/march_scheduler.h` defines a compile-time `MARCH_NUM_SCHEDULERS`
(default 4). `march_sched_init` read the environment variable of the same name
and applied it like this:

```c
g_num_scheds = MARCH_NUM_SCHEDULERS > 0 ? MARCH_NUM_SCHEDULERS : 1;
const char *env = getenv("MARCH_NUM_SCHEDULERS");
if (env && *env) {
    int n = atoi(env);
    if (n >= 1 && n <= MARCH_NUM_SCHEDULERS) g_num_scheds = n;   /* n > 4 dropped */
}
```

The variable could therefore only ever *lower* the thread count. Asking for
more than the build's default was not an error, not a warning, and not
honoured — `MARCH_NUM_SCHEDULERS=14` ran four scheduler threads and printed
nothing. `atoi` also folds every malformed value to 0, which the range test
then discarded just as quietly.

The clamp itself was not wrong: `g_scheds` was
`static march_scheduler g_scheds[MARCH_NUM_SCHEDULERS + 1]`, a fixed-size
table, and the count indexes it on the work-stealing path in
`march_sched_run`. Discarding an unsatisfiable request in silence was the bug.

**Why it matters beyond the missing threads.** Because the cap was invisible,
any parallel-scaling table produced by varying this variable on a machine with
more than four cores was measuring four threads against four threads. A
plateau in such a table reads as "March stops scaling past 4" when the real
statement is "March stopped being given threads past 4".

## What shipped

`runtime/march_scheduler.h`

- `MARCH_NUM_SCHEDULERS` is documented and used as the **default**, not a
  ceiling.
- New `MARCH_MAX_SCHEDULERS` (default 64, raised automatically if a build sets
  a larger `MARCH_NUM_SCHEDULERS`) is the hard bound and now sizes `g_scheds`.
- New accessor `int march_sched_num_schedulers(void)`.

`runtime/march_scheduler.c`

- `g_scheds` is sized by `MARCH_MAX_SCHEDULERS + 1`.
- The environment value is parsed with `strtol` (not `atoi`) and resolved as:
  - a satisfiable count in `[1, MARCH_MAX_SCHEDULERS]` → honoured, silently;
  - `auto` → `sysconf(_SC_NPROCESSORS_ONLN)`, clamped to the maximum, silently
    (the user asked for "whatever fits");
  - above the maximum → clamped, **and reported on stderr naming both the
    request and the bound**, with the `-DMARCH_MAX_SCHEDULERS=N` remedy;
  - non-numeric, or `< 1` → reported, default used. Notably `0` and `banana`
    are now distinguished from a real request instead of both collapsing to
    "ignore".

The compile-time default stays **4**. Making it `sysconf(_SC_NPROCESSORS_ONLN)`
was considered and rejected for this change: a large part of the test corpus is
golden-output and timing-sensitive with respect to the number of scheduler
threads (`test/dune` pins `MARCH_NUM_SCHEDULERS` to 1 or 4 in ~15 rules
precisely because the count is observable), and silently changing the
concurrency of every default run is a much larger, riskier change than fixing
the ceiling. `MARCH_NUM_SCHEDULERS=auto` gives the same capability opt-in.
The default-vs-core-count question is left open deliberately; see the todo
filed alongside this entry.

### Why a bigger static table rather than a heap-allocated one

The report suggested heap-allocating `g_scheds` and checking whether the extra
pointer indirection costs anything on the hot path. Sizing the static table by
`MARCH_MAX_SCHEDULERS` instead avoids the question entirely — the indexing on
the work-stealing path stays a fixed-address index — at the cost of BSS.
`sizeof(march_scheduler)` is dominated by the 4096-slot Chase-Lev deque
(~32 KiB), so 64 entries is ~2.1 MiB of `__bss`. That is zerofill: it does not
enter the binary (a compiled test program measured 79 KB on disk, `__bss`
2,193,368 bytes) and `march_sched_init` only ever touches the entries actually
in use, so unused slots are never faulted in. Measured max RSS of the same
binary: **3.28 MB at 1 scheduler**, 3.49 MB at 4, 7.57 MB at 64 — resident
memory tracks the schedulers actually used, not the table's size.

## Verification

**`test/test_scheduler_count.c` (new)**, built by `test/dune` with the default
`-DMARCH_NUM_SCHEDULERS=4` and `-DMARCH_MAX_SCHEDULERS=8` so that "above the
default" (7) and "above the maximum" (9) are both reachable without spawning a
hundred OS threads. Seven cases: the request above the default is honoured; the
honoured number is the number of OS threads that *actually dispatch green
threads*; an over-maximum request clamps and warns naming both numbers; unset
uses the default; `banana` and `0` warn and fall back; `auto` tracks
`_SC_NPROCESSORS_ONLN`.

The thread-count case is the load-bearing one and is not a restatement of the
counter: 224 green threads record `pthread_self()` while holding every
scheduler busy, and the test asserts the number of *distinct* dispatching OS
threads equals the request. Both directions were proved:

| run | result |
|---|---|
| against the unfixed resolution logic | 6 of 7 fail, including `distinct dispatching OS threads: 4, requested 7` |
| after the fix | 7 of 7 pass, **0 failures in 40 consecutive runs** at load average 142 |
| perturbation control (request 4, still assert 7 distinct) | fails, reporting `distinct dispatching OS threads: 4, requested 7` |

**End-to-end, on a real compiled March program** (`List.pmap_n` over 64
CPU-bound tasks), counting OS threads with `ps -M` while the process ran. The
request is `N` scheduler threads; the process shows `N + 1` because the
preemption daemon is its own thread and scheduler 0 is the main thread:

| requested | OS threads observed | elapsed |
|---|---|---|
| 1 | 2 | 18017 ms |
| 4 | 5 | 4511 ms |
| 10 | 11 | 2137 ms |
| 14 | 15 | 1656 ms |
| 200 | (clamped to 64) | 1005 ms, plus the stderr warning |

## The real scaling table

`List.pmap_n` over 64 tasks of pure integer arithmetic, 14-core M3 Max
(10 performance + 4 efficiency), three runs per setting:

| scheduler threads | runs (ms) | median |
|---|---|---|
| 1 | 2025 / 1984 / 1797 | 1984 |
| 2 | 784 / 999 / 962 | 962 |
| 4 | 342 / 378 / 300 | 342 |
| 8 | 182 / 147 / 132 | 147 |
| 10 | 118 / 152 / 102 | 118 |
| 14 | 105 / 109 / 99 | 105 |
| 20 | 103 / 139 / 109 | 109 |

**Load average during the run: 171.62 before, 177.79 after** (1-minute; the
15-minute figure was ~126). This machine was heavily loaded throughout, which
inflates every ratio — a March process that asks for more threads takes a
larger share of a contended machine, which is why 14 threads beat 1 thread by
~18.9x on 14 cores and why 20 threads is not meaningfully worse than 14.
**Only the shape of the curve is a result here; the magnitudes are not.** A
clean number needs an idle machine.

The old behaviour is the 342 ms row extended flat: every request of 4 or more
resolved to 4. That is the ~5.8x apparent ceiling the report describes.
