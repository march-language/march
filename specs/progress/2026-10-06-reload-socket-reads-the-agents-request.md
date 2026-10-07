# The reload socket read the Agent's in-process request (hcr_role_policy flake)

**Landed:** 2026-10-06. **Area:** runtime, hot code reload (`runtime/march_reload.c`).

## Symptom

Two-node scenario `hcr_role_policy` failed now and then with the node still
alive and nothing on its stderr:

- CI run 37541774570 (merge train B head 2ed83f86a), `two-node (2/3)`:
  `hcr_deploy: read: Connection reset by peer`, then "the role body patch (v2)
  was refused over the socket". A rerun passed.
- Locally on macOS: `hcr_deploy: connection closed` while deploying v4 ("v4
  was refused, but not by the node's policy"), and in another run right after
  the v2 upload ("Artifact uploaded." then `connection closed`).

It looked like it might have come in with merge train B (PR #829: #821, #822,
#824). **It did not.** Measured on macOS, private `HOME` per run, sequential, no
other scenario running at the same time:

| tree | hcr_role_policy failures |
|---|---|
| fad9a9ec9 (main before B) | 0 / 10 |
| 341b98322 (main after B) | 1 / 10 (`connection closed` right after the v2 upload) |

1 in 10 against 0 in 10 tells the two trees apart no better than chance (Fisher
p = 1.0). The deterministic reproducer below fails identically on both trees,
so no bisect across B's three merges was needed. None of B's changes touch the
reload server.

## Cause

The reload socket and the stdlib-only `reload_request` builtin (the control
plane's Agent, `Control.relay_line`, polling `NODE_STATE` every
`MARCH_CONTROL_POLL_MS`) share one dispatch, `handle_line`, since f60a2756a
(2026-09-29). The builtin passes its request through a process-global channel,
`g_vio`, which it sets and clears under `g_req_lock`. `rl_read` and `rl_write`
picked that channel whenever `g_vio` was non-NULL, **whatever the fd**.

The socket thread holds `g_req_lock` only around `handle_line`. It reads each
request *line* outside the lock (`handle_client` → `read_line`, one `rl_read`
per byte). A line read while the Agent's request was dispatching therefore came
from the Agent's in-memory request instead of the socket. That request was
already consumed, so the read hit EOF and the server closed the deploy's
connection mid-batch. The client saw `connection closed`, or `Connection reset
by peer` if it was still writing. If only part of the line was stolen, the
rest of it reached the dispatch as garbage (`ERR unknown_command`).

## Fix

`rl_read` / `rl_write` use the in-memory channel only when `fd < 0`. The
builtin always dispatches with fd -1, and the socket thread always has its
connection's fd, so the socket thread never even reads `g_vio`.
Making `g_vio` thread-local was rejected for two reasons: the builtin runs on
a green thread, and lazy TLS on Darwin may call malloc (see the comment by
`vault_stripe_of_self` in `march_extras.c`).

## Regression test

New two-node scenario `hcr_reload_socket_vs_agent` (single node). The node
calls `Control.relay_line("NODE_STATE")` back to back until a stop file
exists. Meanwhile a perl client sends 2000 `CAS_CHECK` lines on one reload
socket connection and requires every one to be answered `PRESENT`/`MISSING`.

| tree | hcr_reload_socket_vs_agent |
|---|---|
| fad9a9ec9, unfixed | 3 / 3 fail (closed after line 1 twice, `ERR unknown_command` once) |
| 341b98322, unfixed | 3 / 3 fail (closed after line 1) |
| fixed | 3 / 3 pass |

Perturbation check on `hcr_role_policy` itself, on 341b98322, with a
`usleep(30000)` added inside the `g_vio` window of `march_reload_request`:

| tree | hcr_role_policy failures |
|---|---|
| sleep, no fix | 2 / 4 (`v4 was refused, but not by the node's policy: ... hcr_deploy: connection closed`, the local symptom exactly) |
| sleep + fix | 0 / 4 |
| fix, no sleep | 0 / 6 |
