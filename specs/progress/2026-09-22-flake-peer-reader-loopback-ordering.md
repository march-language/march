# DONE 2026-09-22: `peer_reader_loopback` golden line order

**What was done.** The race was between main's `node-a: wrote 3 frames in one burst`
and the server task's first `node-b: ...` line (two green threads; each `println` atomic,
not ordered against the other). node-b now records its lines in a `peer_reader_log` Vault
(`note`), and main prints them after `task_await(srv)` -- the `session_node_fan_loopback`
pattern. The golden is unchanged byte-for-byte; the order *within* node-b's lines (the
reader's frame-delivery order, which is what the fixture pins) is still recorded as it
happened, so the test stays meaningful. Sorting the golden was rejected: it would stop
pinning frame order.

**Red control.** A copy of each fixture with `Process.run("sleep", ["0.3"])` injected
between `Socket.write` and node-a's `println`: the OLD fixture printed
`node-a: wrote 3 frames in one burst` as line 5 instead of line 1 (0/5 runs matched the
golden); the NEW fixture under the same delay matched 5/5. Undelayed, the dune rule
(`dune build --root . --force test/native_peer_reader_loopback.out` + diff against
`test/native/peer_reader_loopback.expected`) matched 20/20.

---

Original todo below.


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
