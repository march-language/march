# Two-node: cache the prebuilt nodes across CI runs

**Filed:** 2026-10-05. Follow-up to
specs/progress/2026-10-05-two-node-parallel-precompile.md.

Restore `$RUNNER_TEMP/two-node-prebuilt` with `actions/cache` before the
`Precompile two-node nodes` step (and the sanitize-gate sweep's dir, which
would need to move out of sanitize.sh's `mktemp -d`), so a PR that changes
neither compiler, runtime nor stdlib compiles nothing. Correctness needs no
new machinery: `--precompile` empties a dir whose stamp differs and skips
nodes already built from identical source, and `compile` re-checks the
stamp and source before using a binary.

Open questions, to check before wiring it:

- The key. `scripts/two-node.sh` would need to print `toolchain_stamp`
  (e.g. `--stamp`) for the key, computed after the Build step. Whether
  `_build/default/bin/main.exe` is byte-reproducible across CI runs of the
  same source (any embedded commit hash or build path makes every commit a
  miss) decides whether this saves anything; measure the stamp on two runs
  of one commit first. If it is not reproducible, key on a hash of the
  compiler's sources instead, and let the stamp check stay the safety net.
- Size: ~90 binaries per shard; check the cache budget.
- This project already rejected a persistent `~/.cache/dune` cache for
  poisoning risk (see the comment above the `ocaml-build` job in ci.yml); the stamp +
  source check is what makes this one different, say so in the step comment.
