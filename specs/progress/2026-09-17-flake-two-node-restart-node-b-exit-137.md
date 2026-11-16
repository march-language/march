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

## Closed 2026-11-11: the harness can no longer SIGKILL a process it did not start

**What reading found.** `kill_node` was never the problem. It reads the pid into a
local, kills, waits and clears the variable before it returns, and `start_node b 2`
runs only after that, so creation 2's pid was never the one it killed (unchanged since
the harness was written, 2026-09-14). Within the `restart` scenario's own harness
process no variable ever names a dead process.

The unguarded path was `cleanup`, and it reaches across harness runs. It sent
`kill -9` to whatever `pid_a`/`pid_b`/`pid_c` held. A variable outlives its process
whenever a node exits before the scenario reaches its `wait_exit` or `kill_node`: a
node that crashed or finished early while the scenario waits on another one (a
`wait_line` that then times out holds the dead pid for `TWO_NODE_TIMEOUT`, 60 s,
before `fail` runs `cleanup`), or a scenario that ends without waiting on a node it
started. Bash reaps a dead child on SIGCHLD, so from then on the pid is free for the
OS to hand out again while the variable still names it. Pids here are handed out in
sequence and wrap at 99999; the machine was allocating about 100 a second when
measured on 2026-11-11 with eight sessions building, so a pid comes round again in
minutes, sooner under a heavier build load. A SIGKILL to that
number lands on whoever holds it now. On a machine running several harness runs at
once (the sighting was on the shared development machine, during a full-inventory
run) that can be another run's node, which then reports exactly this: a complete,
correct trace and `exited 137`.

**The change** (`scripts/two-node.sh`). Both SIGKILL sites, `cleanup` and
`kill_node`, go through `kill9`, which signals only when `ps -o ppid=` says the pid's
parent is this harness. A recycled pid is never the harness's child, so it is
refused. Every decision is appended to `$work/kills.log`, and `fail` prints that log,
so an unexpected 137 can be checked against every SIGKILL the failing run sent.

**Why that removes the race.** The harness had one way to SIGKILL a process other
than the one it meant: a stale pid. With the parent check a stale pid is not
signalled at all, in this run or any concurrent one, so no harness run can produce a
137 in another.

**What is not proven.** The one sighting left no pids, so it cannot be shown that a
recycled pid is what killed that node-b. A SIGKILL from outside the harness (another
session's pattern kill, the kernel under memory pressure) gives the same report and no
harness change prevents it. `runtime/` sends SIGKILL nowhere, so it is not the
program. If a 137 with a correct trace shows up again, the failing run's own
`kills.log` section will be empty and the cause is outside the harness: reopen with
that output.

**Tests.** `scripts/test-two-node.sh` (CI: doc-lint) gained three cases: a pid
variable naming a process the harness did not start survives `cleanup`, survives
`kill_node`, and a node the harness did start is still killed. Run against the old
`scripts/two-node.sh` the first one fails with
`cleanup SIGKILLed pid N, which the harness never started`.

**Loop.** `scripts/two-node.sh restart`, 50 runs in a row on macOS arm64 under a
private `HOME` (load average 25 to 54, seven other sessions building): 50 ok. A first
loop was 49 of 50; its one failure was a bash syntax error from `two-node.sh` being
edited while that iteration was reading it, not a scenario failure, so the loop was
repeated untouched. The sighting was 1 in 4, unreproduced, so 50 green runs show the
scenario still works and say little about the rate.
