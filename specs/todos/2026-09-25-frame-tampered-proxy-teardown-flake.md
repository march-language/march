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
