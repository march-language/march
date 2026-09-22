# DONE 2026-09-22: `credit_backpressure_loopback` golden no longer races the writer actor

**Status: fixed.** The todo's diagnosis (node-b's CREDIT arriving before the third
enqueue) was wrong: the test already sent "go" only after the third enqueue, so
no CREDIT could exist yet. The real race was with node-a's own **writer actor**.
The budget bounds admitted-but-UNWRITTEN bytes (`NodeQueue.depth`, decremented in
`drain` when a frame is written), and the initial credit lets the writer put one
budget (100 bytes) on the wire before the receiver consumes anything. So frames
1-2 (88 bytes) are *written* as soon as the writer runs, and if it ran between the
second and third `enqueue`, depth was 0 and the third frame fit.

**Fix.** The test now waits for the state it asserts on through `NodeQueue.depth`
instead of racing the writer: enqueue 1-2, poll until `depth == 0` (both written
under the initial credit); enqueue 3-4, which can never be written without CREDIT
(88 of 100 bytes of credit already in flight, no "go" sent yet), and assert
`depth == 88` after a 50 ms pause; then the fifth enqueue is refused with
`Backpressure` and not charged (`depth` still 88). The receiver then gets "go",
consumes, its CREDIT drains 3-4 and the retried fifth frame is admitted; receiver
consumed 5. This is the same shape `block_sender_loopback` uses, minus its fixed
sleep.

**Verification.**
- Race demonstrated: the OLD test with a 50 ms `sleep` injected between the
  second and third enqueue (before "go" is sent, so node-b is not involved)
  prints `node-a: third refused with Backpressure: false`, the exact CI diff, 20/20
  runs. The NEW test with the same injected delay, plus a 200 ms delay after the
  fourth enqueue, matches its golden 20/20.
- The new test unmodified: dune rule `test/native_credit_backpressure_loopback.out`
  plus a diff against the golden, then 20/20 repeat runs of the binary.
- Mutations in `stdlib/node_queue.march` (temporary, reverted):
  `DropNew` admits instead of refusing: `fifth refused ... false`;
  `may_write` ignores the credit window: `depth held at 88 ... false`;
  `grant` ignores CREDIT: `fifth admitted after credit: false` (then node-b
  waits for frames that never come, as the old test did).

Follow-up filed: `specs/todos/2026-09-22-block-sender-loopback-fixed-sleep.md`
(the sibling test waits a fixed 50 ms for the writer, the opposite side of the
same race).

---

Original todo (filed 2026-09-17):

# `[P3]` Flake: `credit_backpressure_loopback` golden -- the third frame is sometimes admitted

Seen twice on CI's ubuntu-24.04 `test` job (PR #503, run 35172186859,
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
