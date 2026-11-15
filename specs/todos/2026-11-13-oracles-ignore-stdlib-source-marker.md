# Oracles ignore the `-- compile-flags: --stdlib-source` marker (2026-11-13)

Ocap phase 2b, Task 15 follow-up. Since Task 9 about 20 cluster-plumbing fixtures under
`test/native` (`node_*_loopback`, `monitor_*`, `rpc_auto_enroll`, `close_returns_ok_atom`,
`file_handle_leak_probe`, bench `cluster_frames`, ...) carry the header
`-- compile-flags: --stdlib-source`. `test/test_ir_verify.ml` (`header_compile_flags`),
`scripts/two-node.sh` and `specs/lang/golden/sanitize.sh` read it; `scripts/ir-oracle.sh`,
`scripts/refine-oracle.sh` and `scripts/types-oracle.sh` do not. So the IR oracle skips
those fixtures and refine/types record only `stdlib_internal` errors for them: a change to
the cluster plumbing's IR or refinement results is invisible to all three oracles.

Fix: have each oracle read the marker from the first 5 lines and pass the flag, as
`header_compile_flags` does; prove it RED by perturbing one plumbing module.
