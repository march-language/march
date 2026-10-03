# CI: the HTTP leak check's warm-up; cluster_ap_restart says why it stalls

**Date:** 2026-10-03

## `test (ubuntu-24.04, rest)`: "http server (compiled, end-to-end)", event loop

Failed on three branches (2026-10-02 and 2026-10-03, e.g. #764's run before it
merged) with "server RSS grew 3024-3580 KiB over 20000 requests ... the
handler's result Conn is not being released per request" (bound: 2048 KiB).
Only the event-loop leg failed, only on Linux.

Not a leak. In `ci/Dockerfile.ubuntu` (linux/arm64), the same event-loop server
measured over growing windows grew 2340 KiB over one 20k-request window, then
252, 148 and 84 KiB over windows of 20k, 80k and 160k requests: a one-step
plateau (glibc's heap settling), not growth proportional to requests. macOS
grew 0 KiB at 20k and 80k. The check warmed up with only 1,000 requests, so the
step sometimes fell inside the measured window.

Fix (`test/test_http_native.ml`): the warm-up is 200 rounds (10,000 requests),
not 20. After it, 8 fresh runs in the container measured 0 KiB (event loop)
and 28 KiB (thread pool), every time. Red control: with
`march_http_release_conn` returning early (the leak #755 fixed), both legs
grew ~9 MB per window and failed.

## `two-node (1/2)`: `cluster_ap_restart` "timed out waiting for node-a to exit"

Twice in CI (2026-10-02 on a branch, 2026-10-03 on main at c462e105a), the
same way: node-b restarted and re-offered (creation 2), and node-a's second
session never completed. Node-a printed nothing more. Not reproduced: 12/12 on
macOS, 20/20 in `ci/Dockerfile.two-node`, 15/15 there on one CPU with two busy
loops.

Node-a could not say why: `session` dropped the error, and its waits (120 s for
the new offer, 120 s of retries) outlasted the harness's 60 s for node-a to
exit, so a stall ended in the harness's timeout with node-a still retrying.
Now each failed attempt prints its `Echo_Run.error_message` on stderr (the
harness shows a node's stderr only when the scenario fails), and the waits are
20 s and 30 s, inside the harness's 60 s, so a stall ends in node-a's own
panic. The next CI failure names the cause; this does not fix it.

## `test (macos-15, all)`: `test_hcr_migrate_order` "the old task is running"

#767's own first run failed here (line 620): the test spawned a task, slept a
fixed 20 ms, and asserted the task had already ticked. A loaded macOS runner
had not scheduled it yet. It now waits for the first tick (`wait_until`, 5 s
deadline), as the file's other waits do. 94/94 checks, three local runs.
