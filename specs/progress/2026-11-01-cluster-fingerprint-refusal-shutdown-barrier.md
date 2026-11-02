# Wait for the peer's fingerprint refusal before stopping its sender

`cluster_fingerprint_skew` could report `connection lost` on node B instead
of node A's missing-fingerprint refusal. `SessionNode.abandon_found` queues
the cancellation with `NodeQueue.cast`; returning the local setup error is
not an acknowledgement that B received it. The fixture immediately called
`ClusterNode.stop` on A, closing the link while that refusal was in flight.

The harness now waits for B to finish before releasing A through a file
barrier. Both original expected-output files remain unchanged, including
the precise missing-fingerprint diagnostic and the absence of either
session body. There is no runtime change or timeout increase.

Evidence:

- PR 1046 CI at `d90a5dc`, `two-node (2/3)`, reported this exact discrepancy.
- No November 1 main CI suite ran; the latest main two-node control
  (October 31, job 124564107400) passed this scenario. It was not treated as
  an established main timing flake or bypassed with a CI rerun.
- Unmodified binaries reproduced the exact `connection lost` diagnostic on
  the first local run with `MARCH_NUM_SCHEDULERS=1`.
- The fixed harness passed both with its default scheduler configuration
  and with `MARCH_NUM_SCHEDULERS=1`, the setting that reproduced the failure.
