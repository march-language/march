# `[P2]` `hosted_protocol_change` under ASan: "unexpected message in state S_recv_Hello"

Found 2026-10-05 in the sanitize gate's two-node sweep (PR #784's run): node-a
printed the three old-version hellos and "old offer draining: 3 sessions", then
panicked with

    panic: Hold, role Server: unexpected message in state S_recv_Hello

i.e. right after `Topology.reoffer`, while session 4 (the new version) was
starting, a host's Server endpoint received a message its state does not
accept. That is a delivery going to the wrong session or the wrong host
(an old session's `go`, or a new session's message reaching the draining
actor), not a deadline: no timeout is involved, so scaling in-program deadlines
under ASan (`scripts/two-node.sh` `TIME_SCALE`,
specs/progress/2026-10-05-two-node-asan-time-scale.md) does not cover it.
It did not reproduce in 3 runs under ASan in the Linux container (4 CPUs, 8
busy loops). Plain runs have never shown it; ASan's timing widens whatever
window it is.

Next step: run it in a loop under `MARCH_SANITIZE=1` in `ci/Dockerfile.two-node`
and log, in the hosted `deliver` callback, the session id and host generation
of every delivery around the reoffer.

## Fixed 2026-10-13

**Cause.** This was not a delivery to the wrong session or host. It was a
reorder inside ONE session. A hosted endpoint's `suspend` (the generated
`await_<X>`) runs in the HOST actor's turn. It installs the continuation in
`handlers` and then only *sends* the endpoint actor a `Drain` for what was
parked while the host was not awaiting. `SessionNode.deliver`, running in
the endpoint actor's turn, consumed any delivery that found a continuation
installed, without checking `pending`. So: session 4's `hello` arrives
before the fresh host has run `Start` and is parked; the host parks
(handler installed, `Drain` queued); the client's `go`, sent right behind
its `hello` (the scenario's gate `open4` is already set), is handled by the
endpoint actor before that `Drain`. It finds the `hello` continuation and is
forwarded to the host first. The host, in `S_recv_Hello`, decodes a `Go`
and panics. Only session 4 sends two messages back to back, which is why it
is always session 4. The callback API never hits this, because its drain
runs in the same turn as the install.

**Fix.** `deliver` (stdlib/session_node.march) keeps per-sender FIFO. When
a continuation is installed but something from a sender it takes is
already parked (`has_pending`), the new delivery is parked behind it and
the oldest is drained.

**Test.** test/stdlib/test_session_node.march, "SessionNode delivery:
per-sender FIFO". It forces the interleaving with no timing involved: it
parks one message, installs the continuation as a hosted suspend does
(its `Drain` not yet run), then delivers a second. RED before the fix (the
forward got `go;`, not `hello;`), GREEN after.

**Evidence** (Linux container `march-ci-ubuntu-step6b`, 4 CPUs, 8 busy loops,
`MARCH_SANITIZE=1`, `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`, through
`scripts/two-node.sh` with a precompiled node):
- Unfixed: 5 of 200 runs panicked with this exact message. In each, the
  trace shows session 4's first forward to the new host was the 18-byte `go`
  (`hello` is 21 bytes). One other run failed differently (holds counts;
  see specs/todos/2026-10-13-hosted-protocol-change-holds-count-race.md).
- Fixed: 0 of 200 runs failed.
- Plain build, unfixed, same load: 0 of 300 runs failed. The mechanism does
  not depend on ASan (it is a scheduling interleaving between two actors on
  different scheduler threads), but at plain speed the window is too narrow
  to show up in this scenario.

**Diagnostics.** `MARCH_SESSION_TRACE_HOSTED=1` makes `offer_hosted` print one
stderr line per start / deliver / cancel callback, with the offer (protocol,
role, fingerprint, host pid), the session id, and `from`/`ep`/byte length.
It is read once per offer. Off, it prints nothing, and stdout and the
`.expected` files are unchanged.
