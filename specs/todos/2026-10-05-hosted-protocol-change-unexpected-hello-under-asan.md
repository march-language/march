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
