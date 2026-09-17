# `[P3]` Flake: `credit_backpressure_loopback` golden -- the third frame is sometimes admitted

Filed 2026-09-17. Seen twice on CI's ubuntu-24.04 `test` job (PR #503, run 35172186859,
and once during #500):

```
-node-a: third refused with Backpressure: true
+node-a: third refused with Backpressure: false
```

`test/native/credit_backpressure_loopback.march` fills a 100-byte budget with two 44-byte
frames and expects the third `enqueue` to be refused under `drop_new` before node-b has
consumed anything. node-b only reads after a "go" on control, but its CREDIT for the
frames it then consumes can reach node-a's queue *before* node-a issues the third
enqueue, and the third frame is admitted -- the protocol worked, the interleaving the
golden pins did not happen. Both nodes are tasks in one process; nothing sequences "the
third enqueue" before "node-b's first CREDIT" except node-a being faster.

**What to do.** Make the refusal not depend on timing: send "go" to node-b only *after*
the third enqueue has been attempted (so no CREDIT can exist yet), or assert the
budget arithmetic through `NodeQueue.depth` rather than through a race with the reader.
