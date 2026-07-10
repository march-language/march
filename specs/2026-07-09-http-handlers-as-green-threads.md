# Follow-on: HTTP handlers as green threads (B1)

**Status:** filed, not started. Prereq work (foreign-thread actor bridge)
landed 2026-07 — see specs/plans/2026-07-09-foreign-thread-actor-bridge.md.

Today `march_http_evloop.c` calls the March pipeline inline on evloop
pthreads (evloop_run -> fn(pipeline, conn)); the bridge makes actor ops
*work* from there, but handlers still aren't actors (no receive), a slow
handler blocks an entire evloop thread, and an actor_call blocks the
evloop thread for its duration.

B1 (the BEAM architecture, steps 1-3): at the dispatch point, spawn a
green thread per request instead of calling inline; completion signals
the evloop (eventfd/pipe) which serializes and writes the response.
Evloop threads stop running March code entirely (drop the atomic-RC
forcing). Handlers become full actor citizens. Hard parts: per-request
pending state, out-of-order completion within pipelined keep-alive
batches, backpressure, preserving the iovec-batching fast path.
Full BEAM parity (B2) additionally parks green threads on socket
readiness via a poll set — separable, not needed for conduit.

Driver: forgepm conduit integration (forgepm specs/conduit-background-jobs.md)
runs on the bridge alone; B1 is wanted for slow-handler isolation and
retiring forgepm's direct-connection Repo workaround under load.
