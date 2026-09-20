# DONE 2026-09-19 — a refused `tcp_connect` said "Interrupted system call" on Linux

**Symptom.** `two-node[cluster_crash]` in the ASAN `sanitize-gate` job (ubuntu;
main run 35426001976, PR #524 run 35458723472): node-a reported
`node-b dead: suspect timeout` where the golden pins `connection refused`.
Commit 08389a7b5 had blamed a false suspicion racing the refused redial and
raised the scenario's suspect timeout to 10 s. That was the wrong diagnosis:
the refusal never reached the cluster node at all.

**Reproduction.** Linux container (`march-two-node` image), the scenario's
two binaries prebuilt and run in a loop with node-b killed right after it
joins: 14/20 failures under `MARCH_SANITIZE=1` and 15/20 WITHOUT any
sanitizer. ASAN only changes the timing enough for the harness's own run to
hit it. macOS: 0/25 even under heavy load.

**Cause.** `strace` showed node-a redialling node-b on the doubling backoff
(200 ms, 400 ms, ..., 3.2 s): every redial failed, and none of them counted
as refused. Tracing `ClusterNode.dial_one` showed the error text was
`tcp_connect: Interrupted system call` (once, `Success`), while
`getsockopt(SO_ERROR)` said ECONNREFUSED (111). On Linux, a non-blocking
loopback connect returns EINPROGRESS, so `tcp_connect_impl` parks in
`march_sched_wait_fd` and reads the outcome from SO_ERROR. It then passed
that outcome through `errno` (`errno = so_err; ... saved_errno = errno`).
The green thread can resume on another scheduler thread, and glibc declares
`__errno_location()` `const`, so clang reused the errno address it had
computed before the park, which belongs to the old thread's TLS. That is the same
hoisting hazard `march_sched_send`'s migration-barrier comment describes for
`tl_sched`. The cluster node classifies a dial as refused by the text
(`refused_msg`), so a SIGKILLed peer was only ever declared dead when SWIM's
suspect timer fired. macOS's `__error()` is not `const`, which is why it
never showed there.

**Fix.**
- `runtime/march_scheduler.{c,h}`: `march_errno_now()`, a `noinline` read of
  errno on the thread running the caller now, for code that reads errno
  after a park.
- `runtime/march_http.c` `tcp_connect_impl`: the outcome travels in a local
  (`cerr`) and never goes through errno; the reads after the park
  (`wait_fd` error, the zero-timeout `poll` loop, `getsockopt` failure) use
  `march_errno_now()`.
- Regression: `test/native/tcp_connect_refused_after_park.march` has 8 tasks
  × 40 dials of a closed port, and every error must say "refused". Before the
  fix, on Linux: 146–278 of 320 per run, and 10/10 runs failed. After: 320/320
  in 20/20 runs.

**Verified (Linux container).** cluster_crash through `scripts/two-node.sh`:
10/10 under `MARCH_SANITIZE=1`, 10/10 plain. Prebuilt-binary loop: 0/20
failures both ways, down from 14/20 and 15/20. The full two-node sweep passes.

The scenario keeps its 10 s suspect timeout: with the refusal delivered, the
refused path decides well inside it, and a false suspicion on a loaded
runner is still possible.

Other `march_sched_wait_fd` callers still read errno directly after a park:
[[2026-09-19-errno-after-park-audit]].
