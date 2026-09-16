# `scripts/two-node.sh` picks node-b's port outside the ephemeral range

Shipped 2026-09-15. Harness-only fix; no compiler, runtime or scenario change.

## Symptom

CI's two-node step (`.github/workflows/ci.yml`, which runs every scenario in
sequence) failed intermittently on ubuntu-24.04 with

```
two-node[stall]: panic: listen: tcp_listen: bind failed
```

on PRs that touch nothing the harness exercises.

## Cause

The harness picked node-b's listen port as `40000 + RANDOM % 20000`, i.e.
40000-59999. That sits inside Linux's default ephemeral range
(`/proc/sys/net/ipv4/ip_local_port_range` = 32768 60999), which is where the
kernel draws the *local* port of every OUTGOING connection. The scenarios run
one after another in the same job (`restart` and `skew` immediately before
`stall`), and each opens client sockets to 127.0.0.1; one of those, still held
or in TIME_WAIT, can be sitting on precisely the port the next scenario's
node-b is about to bind. No competing listener ever existed, which is why the
failure looked inexplicable. macOS was less exposed (its ephemeral range
starts at 49152) but not immune.

## Fix

Two changes in `scripts/two-node.sh`:

1. **Choose below the ephemeral floor.** The floor is read from
   `/proc/sys/net/ipv4/ip_local_port_range` where it exists and assumed to be
   the IANA/BSD 49152 otherwise, and the port is drawn from 20000 up to one
   below it. Down there a port is only ever taken by something that asked for
   it by number. The seed mixes `$$` into `$RANDOM`: two harnesses started in
   the same second seed `$RANDOM` identically and used to pick the same
   "random" port as each other.
2. **Retry a collision that happens anyway.** `start_node b` now watches for
   ~300 ms for node-b dying with `bind failed`; if it does, it picks another
   port and relaunches, up to 10 attempts. The retry is deliberately allowed
   only while `port_settled` is 0 — before node-b has ever bound and before
   node-a has been told where to connect. After that the port IS the scenario
   (`restart` restarts node-b on the same port mid-run), so a collision there
   is a real failure and is reported as one. A node-b that dies for any other
   reason is left alone for the scenario's own `wait_line`/`wait_exit` to
   report, unchanged.

The 300 ms is only spent when node-b exits immediately, which is the failure
being looked for; a node-b that binds is detected alive and the wait ends.

## Verification

- All five scenarios pass with the new logic (`monitor_reconnect`, `restart`,
  `skew`, `stall`, `stream`).
- **Retry path fires and recovers.** With the candidate range narrowed to two
  ports and one of them held by a listener, `stall` passed 6/6 — roughly half
  of those runs hit the occupied port first and re-picked.
- **Retry path fails loudly when it should (non-vacuous).** Narrowed to a
  single occupied port, the run ends with
  `two-node[stall]: node-b found no free port in 10 attempts (last 20001)`
  rather than the bare `bind failed` panic. So `bind_failed` really detects
  the condition and the attempt counter really bounds the loop.
- `bash -n scripts/two-node.sh` is clean; the script still runs under bash 3
  (no associative arrays, no `${var,,}`).
