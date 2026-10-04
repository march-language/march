`[P3]` two-node `frame_tampered` flakes at teardown: the proxy panics dialling a stopped node-b

Found during dd step 11b's final scenario sweep (2026-09-25). Its assertions
all hold (node-b drops and counts the tampered frame, 9 of 10 pings arrive),
but node-c, the byte-flipping proxy, sometimes exits 1:

```
panic: node-c: upstream: connection failed: tcp_connect: Connection refused
```

After the stop file, node-b can stop before node-a. node-a's cluster node then
redials through the proxy, and the proxy's per-connection upstream dial
(`test/two_node/frame_tampered/node_c.march:57`) panics when node-b is gone.

**It predates step 11b.** A control on origin/main 08e406f8e, with that tree's
compiler and scenario files, failed 2 of 8 runs with the identical panic. The
step-11b branch failed 1 of 4.

Fix in the fixture: once the proxy has flipped its byte, an upstream dial that
fails should close that downstream connection and keep going (or end the proxy
cleanly), not panic.

## Fixed (2026-10-04)

**Cause.** As filed: once the stop file appears, node-b can stop before node-a.
node-a's cluster node then redials through the proxy, and node-c's `serve` met
the refused upstream dial with `panic`, so node-c exited 1. Every assertion had
already held by then. No runtime bug is involved: a refused connect to a closed
port is correct behaviour.

**Fix (fixture only, `test/two_node/frame_tampered/node_c.march`).** A refused
upstream dial now closes that downstream connection, writes one line to stderr
(`node-c: upstream: ...`, outside the sorted stdout golden), and keeps serving
until the stop file. `conn` does not advance on a refused dial, so
`tamper_conn` still counts only connections that were actually proxied.

**Failure rate, 20 back-to-back local runs each (macOS, load average about 5):**

| tree | failures | symptom |
|---|---|---|
| origin/main before the fix | 7 of 20 | `panic: node-c: upstream: connection failed: tcp_connect: Connection refused`, every one |
| with the fix | 0 of 20 | |

To check the new path really runs, a temporary scenario line copied node-c's
stderr out of the work dir. In 6 more runs, 1 hit the refused redial (stderr
held the `node-c: upstream: ... Connection refused` line) and still passed.

**Still not vacuous.** Two temporary perturbations of node-c, each run once
with the fix in place, both went red:

- No tampering (`tamper_frame` set to -1): node-b reported
  `10 of 10 pings arrived, frames rejected: 0` and no FrameRejected line, and
  node-c's "flipped a byte" line was missing.
- The flip still logged but the original bytes forwarded (`let out = body`):
  node-b again reported `10 of 10 ... frames rejected: 0`. So the node-b golden
  depends on the actual byte flip being refused by the MAC check, not on the
  proxy's log line.
