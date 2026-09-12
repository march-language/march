# A path dep's `source` in `forge.lock` is sometimes an absolute path

**Filed 2026-09-11**, found while validating
`specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md` against the
thirteen real `forge.lock` files on the author's machine.

## The gap

`forge.lock` is a committed, shared artifact, but a path dep's `source` field is
recorded in whatever spelling the manifest used, so it can be machine-specific:

| project | recorded source |
|---|---|
| `test_conduit_app` | `source = "path:../conduit"` |
| `depot_toyapp` | `source = "path:/Users/80197052/code/depot"` |

The second is meaningless on any other machine, and it leaks the author's home
directory into a file that normally goes into version control.

## Why it matters

Not a build break today: nothing reads `source` to *locate* a dep (the only
lockfile read anywhere is `Resolver_lockfile.read_toolchain`, from
`forge/lib/cmd_build.ml`). It matters for two reasons:

1. It feeds `manifest_hash` drift and diff noise: two developers with the same
   `forge.toml` can produce different lockfiles.
2. The offline design above makes the lockfile authoritative for dep identity.
   Once something *does* read `source`, an absolute path becomes a real failure
   rather than cosmetic.

## Options

1. **Normalise to project-relative on write.** Store every path dep relative to
   the project root, so the lockfile is machine-independent. Changes existing
   lockfiles once (a one-line diff per path dep).
2. **Record the path as declared, and additionally record a normalised form.**
   More faithful, more fields, no clear consumer.
3. **Leave it and document that `source` is advisory for path deps.** Cheapest,
   but pushes the problem onto whoever first reads the field.

Option 1 unless someone can name a case where the absolute form is wanted.

## Acceptance

Two checkouts of one project at different filesystem locations, with the same
`forge.toml`, produce byte-identical `forge.lock` files.
