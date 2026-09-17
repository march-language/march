# `[P3]` Flake: `two-node[restart]` node-b (creation 2) exited 137 with a correct trace

Filed 2026-09-17 on one local sighting (macOS, during a full-inventory run of the
harness). node-b's second incarnation printed its complete expected trace, ending in
`node-b: peer closed, delivered 1 message(s)`, and then the harness reported
`node-b exited 137` (SIGKILL). 3/3 passes on immediate rerun.

Nothing in the runtime sends SIGKILL to itself. The harness does, in two places:
`kill_node` (the scenario's deliberate kill of creation 1) and the `cleanup` trap on
exit. A SIGKILL reaching creation 2 means a pid confusion -- most plausibly `kill_node`'s
`wait` on creation 1 returning after `start_node b 2` had already reused the pid slot,
or the previous scenario's `cleanup` (the inventory loop runs scenarios back to back)
killing a pid the OS had recycled.

**What to do.** Reproduce with the inventory loop under load; make `kill_node` capture
the pid before `start_node` can overwrite it and make `cleanup` only kill pids it
started in *this* run (it already does the latter by variable, so the recycled-pid
theory is the one to test first: log the pid at each kill).
