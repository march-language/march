# Two-node: compile every node up front, in parallel

**Date:** 2026-10-05

## Why

A two-node scenario is mostly compiling its nodes (10-200 s each), and both
CI consumers run the scenarios in one serial loop: the `two-node` shards
(~24-31 min each) and the sanitize-gate's ASan sweep (45-60 min of its 85).
The compiles are independent of each other and of the scenarios' timing, so
they can run side by side as long as they all finish before any scenario
starts. Shortening the scenarios' waits was ruled out: they exist to test
timing behaviour, and every cut trades speed for flakes.

## What

- `scripts/two-node.sh --precompile <dir> <scenario>...` compiles every
  `node_<x>.march` of those scenarios into `<dir>/<scenario>/`,
  `TWO_NODE_JOBS` (default 4) at a time through `xargs -P` (bash 3, so no
  `wait -n`). Each compile runs with its own directory as cwd, which is its
  own CAS (`.march/cas/` is cwd-relative and `Cas.write_file` is
  truncate-then-write, not safe to share between concurrent compiles; the
  `~/.cache/march` blobs and the runtime-object archive already use
  pid-suffixed tmp + rename).
- Skipped, and still compiled by their scenario: every node whose
  `scenario.sh` mentions `COMPILE_FLAGS_<x>` (hcr_* / protocol_* nodes built
  against a signing key or baseline generated at run time) and every
  scenario with no `node_<x>.march` (`control_*`, `hcr_role_policy`, which
  build their own app).
- `TWO_NODE_PREBUILT=<dir>`: `compile` copies `<dir>/<scenario>/node_<x>`
  when the scenario set no `COMPILE_FLAGS_<x>`, the prebuilt source copy is
  byte-identical to `node_<x>.march`, and `<dir>/stamp` matches
  `toolchain_stamp` (the compiler binary, the runtime and stdlib sources it
  resolves, `cc --version`, `MARCH_SANITIZE`, `uname -sm`). Anything else
  compiles as before; a stale or partial `<dir>` costs time, never a wrong
  binary. A failed precompile leaves no binary, so the scenario recompiles
  and reports the error in its own context.
- `--precompile` into a dir with a different stamp empties it first; into a
  non-empty dir with no stamp it refuses (exit 2). A rerun with the same
  stamp skips every node already built from identical source, which is what
  a cross-run cache of `<dir>` (specs/todos/2026-10-05-two-node-prebuilt-cache.md)
  needs.
- CI: a `Precompile two-node nodes (K/2)` step (25 min limit; job limit
  80 -> 105) before the scenarios step, exporting `TWO_NODE_PREBUILT` through
  `$GITHUB_ENV`. sanitize.sh's two-node sweep precompiles its list with
  `MARCH_SANITIZE=1` the same way.

## Verified (locally, macOS)

- Selection: over fan, restart, wrong_secret, hcr_remote_msg_epoch,
  protocol_mixed_local, control_plane, setup_timeout it built 11 nodes,
  leaving out hcr_remote_msg_epoch's b, protocol_mixed_local's a and all of
  control_plane. A second run compiled 0.
- fan, restart, wrong_secret, hcr_remote_msg_epoch (prebuilt a, flagged b
  compiled in-scenario) and setup_timeout pass with `TWO_NODE_PREBUILT`.
- The prebuilt path is really taken: replacing fan's prebuilt node_a with
  restart's makes fan fail ("timed out waiting for node-a to print"). With
  that wrong binary still in place, a changed source copy, a changed stamp,
  or `MARCH_SANITIZE=1` each fall back to compiling and pass.
- No wall-time figure: the machine's load average was 114 from other
  sessions. The CI step prints "B of N nodes compiled in S s"; compare the
  scenarios step against main's.
