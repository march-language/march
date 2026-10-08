# CI: two macOS jobs instead of six, sanitize-gate in three shards, PR-sized determinism corpus

**Landed:** 2026-10-07 (third PR from the 2026-10-07 CI audit; see
`2026-10-07-ir-validity-gate-parallel.md` and `2026-10-07-parallel-test-suites.md`)

Measured on run 37567885999: ~370 Linux and ~88 macOS job-minutes, six macOS jobs
against an org-wide cap of five, and `determinism` (51 min) and `sanitize-gate`
(36-42 min) as the slowest Linux jobs once the codegen shard is fixed.

**macOS: six jobs to two.** `test (macos-15, all)` stays. A new `macos-checks` job
replaces `ocaml-build (macos)`, three macOS `property-tests` shards and
`conformance (macos)`:
- It builds once and runs every property group except the interp-vs-compiled oracle in
  one process. The group list comes from `test_properties.exe list`, regex-escaped,
  so a new group runs without a workflow edit.
- It also runs `@vault-scale`, the one conformance check whose answer depends on the
  OS. Everything else in conformance is frontend-only (`--check`) or was already
  skipped on macOS.
- Checked locally: the derived filter is the 10 non-oracle groups, all 39 of their cases
  ran and passed (213 s), and none of the oracle group ran.

**sanitize-gate: three shards.** `sanitize.sh` gained `SANITIZE_TWO_NODE_ONLY=1` (skip the
golden and native sweeps). Shard K sets `SANITIZE_TWO_NODE_SHARD=K/3`; shard 1 also runs
golden + native. `scripts/two-node.sh --list K/3` deals the 81 scenarios 27/27/27,
disjoint, with their union equal to the whole list, and three `control_*` per shard. The
two-node sweep was ~31 of the job's ~40 minutes. Step limit 85 → 45 per shard.

**determinism:** `--corpus small` (~30 programs) on pull requests, `--corpus all` on pushes
to main. A drift only a non-snapshot program shows is caught by the next main run.

**Removed from conformance:**
- The refinement coverage-audit ratchet. It read the `user + stdlib` slice of
  `stdlib/list.march`, which `test/refine_audit/corpus.baseline` pins exactly, and
  refinecheck's `audit-baseline` test also enforces a corpus Unenforced ceiling of 0.
- `dune fmt 2>&1 || true`, which could never fail. `dune build @fmt` fails today on 30
  files, so making it a real check means formatting the tree first (not done here).

Not verified locally: the ASAN sweeps themselves (they no-op on a Mac running
endpoint-security software), and anything only a CI run shows. This PR's CI run is the
check.
