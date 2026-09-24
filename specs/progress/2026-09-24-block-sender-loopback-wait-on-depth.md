# DONE 2026-09-24: `block_sender_loopback` waits on `NodeQueue.depth`, not a fixed 50 ms

**Fixed.** `test/native/block_sender_loopback.march` no longer sleeps 50 ms after
enqueueing frames 1-2 and hopes node-a's writer has run. It polls
`NodeQueue.depth(q) == 0` with the same `wait_depth` helper
`credit_backpressure_loopback` uses (10 ms steps, at most 500 tries, about 5 s).
If the writer never gets there it panics with
`node-a: writer never wrote frames 1-2 under the initial credit (depth N after 5 s)`
rather than letting frame 3 be refused and the golden diff read `false` with no
explanation. The printed lines are unchanged, so
`test/native/block_sender_loopback.expected` does not change.

**Verification.**
- Dune rule `test/native_block_sender_loopback.out` builds; its output matches the
  golden (`diff` exit 0); then 20/20 repeat runs of the built binary exit 0 and
  match the golden.
- Failure path, checked on a scratch copy outside `test/native/` with the wait
  target changed to an unreachable depth: exits 1 with the panic message above.

---

Original todo (filed 2026-09-22):

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
