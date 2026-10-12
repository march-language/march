# `forge deps`: capability gate for a hand-edited upgrade

Done 2026-10-11. One bullet of
`specs/todos/2026-08-04-dependency-cap-audit-followups.md` ("`forge deps`
after a hand-edited version bump is not gated"); that todo stays open for the
registry cross-check, which is blocked on registry capability notarization.

## The open questions, and the answers

The todo held this back on two questions: what an unacknowledged widening does
to a `forge deps` that is also the offline/restore path, and which flag
acknowledges it there.

- **The restore path is never gated.** The gate analyzes only the lock entries
  the re-resolve added or moved (`Cmd_audit.touched_entries`, the same diff
  `forge add` uses). Installing what forge.lock already says moves nothing, so
  a fresh clone, CI or `--offline` never analyzes a dependency and never needs
  a flag.
- **A refused change** prints the delta and writes forge.lock back
  byte-for-byte (removes it if there was none), exit 1. forge.toml is the
  user's own edit and is kept, so the next `forge deps` re-resolves and refuses
  again until the change is accepted. A registry or git dependency is built
  from the coordinate forge.lock names, so the old version stays in use; the
  fetched copy stays in the dependency cache, as after a refused `forge add`.
- **The flag is `--accept-caps`**, the same one `forge add` takes: it keeps the
  change and merges the moved entries' sets into forge.caps.lock.
- **No forge.caps.lock** means the project has not adopted the audit, and
  `forge deps` stays a plain, silent install.

## Code

- `Cmd_audit.deps_with_gate ~accept ~resolve` (forge/lib/cmd_audit.ml) wraps
  the install. The gate lives outside `Cmd_deps.run` because `forge add` calls
  `Cmd_deps.run` itself and runs its own gate (which also restores
  forge.toml).
- `Cmd_audit.gate_dependency_change` takes `?for_deps`: silent without a
  baseline, and the refusal names `forge deps --accept-caps` and says the
  forge.toml edit was kept.
- `forge deps` gains `--accept-caps` (forge/bin/main.ml).
- `forge deps update` is unchanged: it moves a git branch dependency's
  checkout but does not rewrite forge.lock, so there is no lock change to gate.

## Tests

`forge/test/test_add_cap_gate.ml`, group "forge deps":

- `hand edit is gated`: forge.toml repointed from `clock` (IO.Clock) to a copy
  that also needs IO.Process. Refused with the delta
  `! clock — now ALSO needs: IO.Process`, forge.lock restored byte-for-byte,
  forge.toml kept, forge.caps.lock untouched; refused again on a second run;
  `--accept-caps` locks it, records the new set, and `forge audit` passes.
- `restore is not gated`: a deliberately stale baseline that any analysis
  would refuse; `forge deps` on an unchanged lock passes and analyzes nothing.
- `no baseline: plain install`: the same hand edit without forge.caps.lock
  installs with no capability output.
