# `forge add` / `forge outdated`: capability gate against forge.caps.lock

Done 2026-09-28. One bullet of
`specs/todos/2026-08-04-dependency-cap-audit-followups.md` ("Wire into
`forge add` / `forge outdated`"); that todo stays open for the registry
cross-check and for gating a hand-edited `forge deps` upgrade.

## What changed

- **`forge add`** (`forge/lib/cmd_add.ml`). After resolving, it diffs the old
  and new forge.lock (`Cmd_audit.touched_entries`: new names, or a moved
  source/version/commit/tree hash) and hands those names, plus the added name,
  to `Cmd_audit.gate_dependency_change`:
  - no forge.caps.lock: prints each touched dependency's declared set and a
    hint to record a baseline; never blocks;
  - with one: analyzes the touched dependencies in the baseline's mode and
    diffs them against their entries. An escalation (`Added` with caps, or
    `Widened`) or, in inferred mode, an unanalyzable touched dependency is
    refused: the delta is printed, forge.toml and forge.lock are written back
    byte-for-byte (or forge.lock removed if it did not exist), exit 1.
  - `--accept-caps` keeps the add and merges the touched dependencies' sets
    into forge.caps.lock, leaving every other entry as it was.
  The lockfile is technically written by `forge deps` and then restored, not
  withheld; the observable result (nothing kept without acknowledgement) is
  what the todo asked for.
- **Speed.** `Cmd_audit.collect` takes `?only`: the walk still visits every
  dependency, but only the named ones are parsed or run through `march caps`.
  A cold `forge add` against an inferred baseline therefore pays one
  `march caps` per touched dependency, and the existing per-dependency cache
  makes a repeat free. Pinned by the inferred test (untouched dependency's
  run count unchanged; second add is a cache hit).
- **Baseline mode.** forge.caps.lock now records `mode = "declared"` or
  `"inferred"` above the first `[[package]]` (`read_baseline` ignores it, so
  older forge still reads the file). The gate and the outdated preview compare
  in that mode; `forge audit` warns when checked in the other mode. A file
  without the line reads as unrecorded and is compared as declared.
- **`forge outdated`** (`forge/lib/cmd_outdated.ml`). For each outdated
  registry dependency it fetches the newest release through
  `Dep_refetch.cached_or_download` (checksum-verified, tarball cache), extracts
  it to a scratch directory, and prints `caps: asks for NEW capabilities: …`,
  `caps: no new capabilities`, or `caps: unknown (reason)` under the row. The
  comparison base is the dependency's forge.caps.lock entry, else the installed
  copy's set.

## Evidence

Same scenario (app depends on `clock` [IO.Clock], baseline recorded, then
`forge add fs --path ../fs` where fs declares IO.FileWrite):

- origin/main: `done.`, exit 0, fs in forge.toml; the next `forge audit`
  exits 1 with `+ fs — new dependency, declares: IO.FileWrite`.
- this change: the same delta printed by `forge add`, exit 1, forge.toml and
  forge.lock unchanged, `forge audit` still `capabilities unchanged`;
  `--accept-caps` keeps it and records `fs = ["IO.FileWrite"]`.

Tests: `forge/test/test_add_cap_gate.ml` (12 cases; fixtures are
`mod X do ... end` modules and a case pins that they parse to a non-empty
surface declaring what the cases assume). Not covered: `fetch_release`
against a live registry (the line-building logic is tested on local trees).
