# A path dep's `source` in `forge.lock` is recorded relative to the project

Fixed 2026-09-17. Closes
`specs/todos/2026-09-11-lockfile-path-dep-source-is-sometimes-absolute.md`,
which was found while validating the offline/versioned dep-cache design against
the thirteen real `forge.lock` files on the author's machine.

## The gap

`forge.lock` is a committed, shared artifact, but a path dep's `source` was
stored in whatever spelling the manifest used:

| project | recorded source |
|---|---|
| `test_conduit_app` | `source = "path:../conduit"` |
| `depot_toyapp` | `source = "path:/Users/80197052/code/depot"` |

The second is meaningless on any other machine and leaks a home directory into
version control. It also feeds `manifest_hash` drift — `content_hash` takes the
source string — so two developers with identical `forge.toml` files produced
different lockfiles.

## Fix

`Cmd_deps.relativize_to_root ~root p` expresses an absolute path relative to
the project root, walking out with `..` where needed, and returns an
already-relative declaration untouched. `install_dep` takes the project root
(the `bfs_install` walk already had it) and records the normalised spelling —
in the lock entry AND in the string handed to `content_hash`, so the hash
follows the recorded source rather than the declared one.

Falls back to the absolute path only when no relative spelling exists (a
different volume, or a root that is itself relative).

Option 1 of the three the todo listed. Option 3 (leave it, document `source` as
advisory) was rejected for the reason the todo gives: the offline design makes
the lockfile authoritative for dep identity, and once something reads `source`
to LOCATE a dep, an absolute path stops being cosmetic.

## Effect on existing lockfiles

A one-line diff per absolute path dep, once, plus the `manifest_hash` that
depends on it. Relative declarations — the majority — are byte-identical.

## Verification

Five cases in `forge/test/test_regression.ml`, including the todo's stated
acceptance criterion directly: `/Users/alice/code/app` + `/Users/alice/code/conduit`
and `/home/bob/src/app` + `/home/bob/src/conduit` both record `../conduit`.
