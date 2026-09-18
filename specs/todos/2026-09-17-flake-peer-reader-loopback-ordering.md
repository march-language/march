# `[P3]` Flake: `peer_reader_loopback` golden line order

Filed 2026-09-17 on one CI sighting during the #500 series (log not retained). The
fixture (`test/native/peer_reader_loopback.march`) has node-a write three frames in one
burst and node-b's single `PeerReader.serve` hand each to its consumer; the golden pins
the consumers' prints in order.

The frames' *delivery* order is fixed by the reader; what is not fixed is the order in
which two consumers' `println`s reach stdout when the consumers are separate actors or
tasks -- the same shape as the `node_discovery` tear
([[2026-09-14-distributed-plane-known-gaps]] A) after the `writev` lock made lines
atomic but not ordered across procs.

**What to do.** Reproduce under load (`scripts/run-tests.sh` while a build runs pegged
the box to load ~20 during the #500 work, which is when it was seen), and either have
the consumers record into one vault and print from one place at the end (the
`session_node_fan_loopback` pattern) or sort the golden.
