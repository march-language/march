# CI: macOS runs only OS-sensitive tests; actions off Node 20; macOS jobs on macos-26

**Landed** 2026-11-02.

## Why

`test (macos-15, all)` ran a median 51 min in the week of 2026-09-28 and 78 min
by the week of 2026-11-02, against a 75 min step timeout: of 34 runs in
October where macOS failed and Linux passed, 25 were that timeout. The same
month showed what macOS actually catches that Linux does not: two real bugs,
both in running native binaries or listing files (`js_bundle` file order,
fixed in dd5082acd; the `native_actor_state_released` SIGILL, still open in
`specs/todos/2026-10-07-flake-actor-state-released-macos-exit.md`). The rest
were timing thresholds on a slow runner. Neither a higher timeout (raised
45 -> 75 in September, PR #1051 proposed 105) nor sharding macOS (measured in
September to double its job-minutes on a 5-slot org-wide pool) fixes that.

## What changed

- **Run less on macOS.** Under `MARCH_CI_SKIP_OS_INDEPENDENT=1`, `run_codegen`
  and `run_compiler` now run only the groups named in `test/run_codegen.ml` /
  `test/run_compiler.ml` (`Test_helpers.keep_os_sensitive`; a name matching no
  group fails the run). Kept: the REPL JIT, debug info, the RC trace runtime,
  SIMD, struct/extern ABIs, float codegen, signals and the cross link (the
  macOS runner is CI's only arm64 test host); linking, the sandbox, binary
  contents, the concurrent-compile race, hot reload and sessions. That is
  ~10% of `run_codegen`'s local time and ~40% of `run_compiler`'s.
  Every `test/native` compile-and-run fixture still runs on macOS; those are
  where macOS caught bugs Linux missed.

  The first version of this PR was a drop list chosen by shimming `clang` and
  `zig` to log which test case called them (`MARCH_TEST_JOBS=1`, cold CAS,
  private HOME): ~30% of `run_codegen` and ~60% of `run_compiler`. A macOS
  timeline then showed why that was not enough: the two suites started 29
  and 40 min into the Test step, behind the `test/native` compiles, so even a
  shorter tail ended near 55 min. Hence a keep list: a new group in these two
  suites runs on Linux only until someone adds it.
- **Node 24 actions.** checkout v7, upload-artifact v7, download-artifact v8,
  setup-node v7, cache v6, github-script v9, action-gh-release v3.
  `mlugg/setup-zig@v2` still declares node20 (no newer release); GitHub runs
  it on Node 24.
- **macos-26** for CI's `test` and `macos-checks`. `build.yml`'s release leg
  stays on macos-15, the minimum macOS we ship for. The opam cache key
  (`.github/actions/opam-deps`) now names the OS release, so a switch built on
  macOS 26 is never restored into a macos-15 release build.

## Not verified here

The macOS job's new wall time is an estimate until CI runs it (expected well
under the 75 min step timeout).

## Follow-ups from the PR's first CI run

- The new cache key made every job build a cold opam switch. On macos-26 that
  took setup-ocaml ~6 min (compiler build) plus ~5.5 min of `opam install`, so
  both macOS jobs ran past their 12 min toolchain step during the cache save,
  which left the cache unwritten. The macOS toolchain steps now get 20 min.
- The cold switch pulled in js_of_ocaml 6.5.0, which broke the browser REPL's
  deep-recursion smoke case. Pinned `< 6.5`; filed
  `specs/todos/2026-11-02-js-of-ocaml-6-5-browser-repl-stack-overflow.md`.
