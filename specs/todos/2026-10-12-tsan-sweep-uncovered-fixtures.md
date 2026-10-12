`[P4]` TSAN sweep: the observe / shell / cluster-harness / FFI fixtures were not exercised

The 2026-10-12 TSAN sweep (fixes in `specs/progress/2026-10-12-tsan-*.md` and
`2026-10-12-send-block-guard-stale-tls.md`) built each `test/native/<name>.march` that has
an `.expected` file with `MARCH_SANITIZE=thread`. It ran each one standalone at 1, 2 and
14 schedulers. Coverage was 336 of 359 fixtures, 1008 runs.

The sweep found **no** race inside the distributed / cluster / HCR / observe / shell
runtime files (`march_observe*.c`, `march_shell.c`, `march_reload.c`, `march_remote_registry.c`,
`march_trace.c`, ...). Every report from a cluster fixture (`cluster_*`, `node_*`,
`session_node_*`, `topology_place`, ...) was in the scheduler or core runtime, and all
of those are fixed. The sweep did not drive those subsystems the way their dune rules
do, though:

- **Not built standalone (23):** the FFI fixtures (`ffi_codec`, `ffi_codec2`,
  `ffi_interp_shim`, `ffi_optres`) need their C objects linked. The JS-target fixtures
  (`js_*`) are not native programs. The multi-file ones (`qctor_collision`,
  `xmod_ctor_collision`, `forge_top`) need `MARCH_LIB_PATH`. The rest are the
  shell / observe fixtures (`shell_*`, `observe_debug_nokey`, `observe_which_source`)
  and the `.stderr`/`.order` side-expectations.
- **Built, but only reach "ready" without their client:** `observe_counters`,
  `observe_crashes`, `observe_debug`, `observe_sched`, `observe_snapshot`,
  `observe_types_hr`, `diagnose_runaway`, `shell_node`. Their dune rules start a
  client (`observe_snapshot_check.exe`, `forge diagnose`, `shell_check.exe`) against
  the program's socket. Standalone, they idle until the SIGTERM deadline, so the
  observe socket thread and the shell were never driven.

To close: extend the sweep with a TSAN-mode variant of those dune actions (the same
`system` strings, with the program compiled under `MARCH_SANITIZE=thread`). Run them
at 2 and 14 schedulers.
