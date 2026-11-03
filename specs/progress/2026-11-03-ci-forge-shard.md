# CI: forge/test split out of the Ubuntu `rest` shard

**Landed** 2026-11-03.

## Why

`test (ubuntu-24.04, rest)` was the workflow's long pole: 46 min, 45 of them in
its Test step (main, run 41574061003). It was one `dune runtest` minus the three
big suites, CPU-bound on a 4-vCPU runner: ~15 min of fixture compiles before the
first suite finished, then everything else together. The heaviest suites were
forge's hot-reload ones:

| suite | time in that run |
|---|---|
| `upgrade-from` (7 cases, 3 at a time) | ~3,540 s of case time |
| `deploy-e2e` | 970 s |
| `march-stdlib` | 708 s |
| `errors` | 608 s |
| `march-lsp` | 321 s |
| `hcr-manifest-diff` | 304 s |
| `release_build` | 253 s |
| `march_jit` | 253 s |
| `march-eval` | 237 s |
| `build_check` | 211 s |

## What changed

- New matrix leg `test (ubuntu-24.04, forge)`: `dune build @forge/runtest`.
- `rest` is now `MARCH_CI_RUNTEST_SPLIT=1 dune build @test/runtest @lsp/runtest`.
  Only `test/` (with `test/dap`, `test/refactor`), `lsp/test` and `forge/test`
  declare tests. `rest` first fails if a dune file anywhere else declares one,
  so a new test directory cannot silently run on no Ubuntu shard. That check was
  run on a probe `lib/probe/dune` holding `(test (name foo))`: it named the file.
- macOS `all` is unchanged: still one `dune runtest`.
- Cost: one more Linux job (~2 min of setup and build) on the 20-slot pool, no
  macOS change.

`@forge/runtest` alone passed locally, so forge's stanzas declare all their deps.
`test/` and `lsp/` reach forge only through the `march_forge` library, which
their stanzas declare.

## Flake fixed on the way

`test_reconcile` `push 0` ("a-1 received SIGHUP") failed once in the local
forge-only run (load average 14). The stand-in node is a shell that traps
SIGHUP, and the test slept 0.3 s to "let each shell install its trap". A
SIGHUP sent before the trap is installed kills the shell, so no mark appears.
The shell now writes `<marks>.ready` after `trap`, and the test waits for both
ready files.
