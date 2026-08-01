# Current State (as of 2026-07-31, the default HTTP pool is elastic — no more stranded connections)


**The fixed thread pool's concurrency cap is gone.** `connection_thread` owns a
connection for its whole keep-alive lifetime, so with a fixed pool of N workers
the server served at most N concurrent connections and silently stranded the
rest — accepted by the kernel, never read. `pool_grow_if_starved` now runs on
every dequeue: a worker that is about to park increments `g_pool.busy` first,
and if that leaves no idle worker it starts one more, up to `max_size`.

*Why growth is one-at-a-time and not in blocks:* connections arrive one at a
time, so single-step growth tracks demand exactly, and a burst that closes
again leaves the pool sized to its peak concurrency rather than to a rounded-up
block.

*Why `threads` is allocated at `max_size` upfront:* growth writes into slots
past the initial run while other workers are live, so the array must never be
reallocated after the workers start.

*The shutdown race, and why the `shutdown` test sits inside the lock.*
`march_http_pool_stop` sets `shutdown`, then takes the queue lock and
snapshots `size` as the set of threads it will join. A first draft of
`pool_grow_if_starved` checked `shutdown` *before* acquiring the lock, as a
cheap early-out. That is a use-after-free: the grow could read `shutdown == 0`,
block on the lock while `stop` took its snapshot and released, then acquire the
lock and create thread number `size` — one past the snapshot. That worker is
never joined, and `stop` proceeds to `pthread_mutex_destroy` /
`pthread_cond_destroy` the very primitives it is about to wait on. The check is
now the first thing done *under* the lock, with acquire ordering against
`stop`'s release store, so a grow either completes before the snapshot (and is
counted in it) or observes shutdown and bails. Found by review, not by a test —
it needs a specific interleaving during shutdown and would be near-impossible
to reproduce on demand.

**Measured at c=256, order-swapped and repeated (wrk -t4 -c256 -d8s):**

| | established | unread `Recv-Q>0` | req/s | avg latency | in-flight |
|---|---:|---:|---:|---:|---:|
| fixed pool (before) | 256 | **228** | 30,774 / 30,625 | 0.90 / 0.91 ms | 27.7 / 27.9 |
| elastic pool (after) | 256 | **0** | 29,261 / 29,068 | 8.67 / 8.76 ms | 253.7 / 254.6 |

In-flight is throughput × latency. The before column clamps at `pool_size`;
the after column tracks offered concurrency. Reported latency rising ~9× is the
correct result, not a regression — the old average covered only the 28
connections that were being served. Throughput drops ~5% because the box's
~30k req/s ceiling is client/kernel-side, so serving 9× the connections buys
no additional throughput and costs some scheduler overhead; the trade is
correctness for 5% at a ceiling that is not March's.

`HttpServer.max_connections` is now enforced as that ceiling. It had been
accepted and discarded (`(void)max_conns`), which is part of why the real limit
looked like an accident of CPU count.

**Also removed:** `march_response_send_plaintext`, a TechEmpower `/plaintext`
fast path hardcoding `Content-Length: 13` and the body `"Hello, World!"`.
Reaching it meant bypassing the user's March router, so the program under
benchmark would never run. Zero callers, ever.

**Doc corrected:** `specs/features/http-and-networking.md` described the event
loop as the default. It has not been since it was made opt-in behind
`MARCH_HTTP_EVLOOP=1`; the thread pool is what every March HTTP server runs
unless that variable was set at compile time.
