# `[P3]` Latent flake: `block_sender_loopback` waits a fixed 50 ms for the writer

Filed 2026-09-22 while fixing `credit_backpressure_loopback` (see
`specs/progress/2026-09-22-flake-credit-backpressure-loopback-timing.md`).

`test/native/block_sender_loopback.march` enqueues frames 1-2, then sleeps a fixed
50 ms (`Process.run("sleep", "0.05")`) on the assumption that node-a's writer actor
has by then written both under the initial credit, so `depth` is 0 and frames 3-4
both fit the 100-byte budget. If the writer has not run within 50 ms (a loaded CI
box), `depth` is still 88 and frame 3 is refused, so the golden line
`two more queued behind the credit line: true` would read `false`. Not seen on CI
yet; it is the opposite side of the race that flaked `credit_backpressure_loopback`.

**What to do.** Replace the fixed sleep with a bounded poll until
`NodeQueue.depth(q) == 0`, as `credit_backpressure_loopback`'s `wait_depth` does.
