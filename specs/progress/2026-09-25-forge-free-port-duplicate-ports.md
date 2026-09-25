# `forge run --processes` could give two pools the same cluster port

Fixed 2026-09-25.

## Symptom

CI run 36098093660 (PR #645, `test (ubuntu-24.04, rest)`) failed
`forge run: --processes: one process per pool; SIGINT drains and stops all`:

```
forge run: starting back-1 (pool back, port 33787)
forge run: starting front-1 (pool front, port 33787)
[front-1] topology: cluster_node: listen on 33787: tcp_listen: bind failed
```

## Cause

`Procs.free_port` bound a socket to port 0, read the port back and closed the
socket. `Topology_run` called it once per slot, and `Upgrade_test` once per test
binary, back to back. Once a socket is closed, nothing stops the kernel handing the
same port to the next bind-to-0, so two slots could get the same port. The first
process to start took it and the second failed to listen.

## Fix

`Procs.free_ports n` binds all `n` sockets, reads every port, then closes them all.
While they are all held open, the kernel cannot give out a port twice, so the list
has no duplicates. Both call sites that assign several ports at once
(`Topology_run.start_processes` and `Upgrade_test`) use it now. `free_port` is
`free_ports 1`.

Each port can still be taken by another program between the close and the child's
`listen`, as with any such helper. That is a separate race, and much less likely.

## Test

`forge/test/test_procs.ml`: `free_ports: no duplicates` asks for 64 ports and checks
they are all distinct. It states the contract; it was not shown to fail against the
old per-call helper locally (the collision was seen on Linux CI, not reproduced on
macOS). The fix holds by construction, because the sockets are held open together.
