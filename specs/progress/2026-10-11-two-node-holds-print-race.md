# DONE 2026-10-11: two ordered two-node scenarios raced a print against the session's end

## Symptom

main's last finished CI run (2026-10-09) failed `sanitize-gate (1/3)` on
`two-node/cluster_ap_local`. No sanitizer reported anything: node-a printed the right lines in
the wrong order, `PingServer holds after finish: 0` after `Client: pong 42`. The scenario sets
`ORDERED=1`, so order is part of the golden.

## Cause

`PingServer`'s handler sends the pong inside `finish(send_Pong(...))` and printed
`holds after finish` afterwards. The client prints `pong` as soon as the pong arrives, so nothing
ordered the two prints. The server usually won, and under the slower sanitizer build it lost.

`two-node/hosted` has the same shape on node-b, not yet seen failing: `ConsActor` printed
`holds after finish` after `finish`, which closes the session and lets `main`'s `host_Cons` return
and print `Cons: closed`.

## Fix

In both, the handler records the count in a Vault instead of printing it, and `main` prints it after
the session's end (`holds_after_finish` waits for the record). `cluster_ap_local`'s golden moves
the line after `Client: hosted session done`. `hosted` prints it just before `Cons: closed`, so its
golden is unchanged. `hosted`'s node-b now declares `IO.Clock` for the wait.

## Red, then green

A 300 ms delay in the handler, before the print or the record:
- **main's code:** both scenarios fail with exactly the reordering CI saw.
- **this code:** both pass.

Each also passes three times without the delay (`scripts/two-node.sh <scenario>`). A sanitized build
was not run locally (ASan binaries hang on this macOS); the CI `sanitize-gate` shards run it.
