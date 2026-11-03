# `[P3]` `forge run --processes` stops its pools one at a time

**Filed** 2026-10-13, while fixing
`specs/progress/2026-10-13-topology-drain-continuous-initiators.md`.

`Procs.stop_all` (forge/lib/procs.ml) sends SIGTERM to one pool's process group,
waits for it for up to `[drain] hard_ms` + 2 s, and only then moves to the next (in
reverse start order). A Ctrl-C on a run whose pools each take their full drain so
takes the SUM of the drains (3 pools x 122 s with the defaults) instead of the
longest one, and a pool still waiting gets no signal at all. With the drain fixes
above a pool normally drains in about a second, so this mostly matters when sessions
really do run long.

Signalling every pool at once was presumably avoided so initiators (started last)
stop before the roles they use. Options: signal all at once (servers keep serving
the sessions already running while they drain, and the initiators now refuse new
sessions from the first signal), or keep the order but signal the next pool as soon
as the previous one has *started* draining rather than when it has exited. Decide,
then add a `test_forge` case that a 3-pool run stops in about one drain, not three.
