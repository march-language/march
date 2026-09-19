# DONE 2026-09-18 — `tcp_connect_timeout` / `Socket.connect_timeout`

A prerequisite of the cluster node service ([[2026-09-18-cluster-node-service]]):
its redial loop dials peers behind a partition, where `iptables -j DROP`
answers a SYN with nothing at all, and `tcp_connect` then waited out the
kernel's SYN retries (~75 s on macOS, ~127 s on Linux).

- Runtime: `march_tcp_connect` and the new `march_tcp_connect_timeout` share
  `tcp_connect_impl`; the park on writability (`march_sched_wait_fd`) takes an
  absolute deadline, and `MARCH_FDWAIT_TIMEOUT` becomes `ETIMEDOUT`
  ("tcp_connect: Operation timed out"). `timeout_ms <= 0` is unbounded, i.e.
  `tcp_connect`. The name lookup is not bounded (getaddrinfo has no deadline).
- Interpreter: a non-blocking `Unix.connect` plus `select` for the same bound.
- Every builtin site: typecheck type + capability (`IO.NetConnect`),
  `cap_infer`, `cap_symbols`, `llvm_builtins` (entry and `PDeclare`), `defun`,
  `borrow`, `purity`, and the `test_codegen` preamble golden.
- Stdlib: `Socket.connect_timeout(host, port, ms)`.

Exercised by the cluster node's dialer on every dial, and under a real SYN
drop by `test/two_node/cluster_partition` (root/iptables; macOS through
`scripts/two-node-docker.sh`).
