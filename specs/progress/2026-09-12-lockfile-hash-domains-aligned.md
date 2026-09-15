# `forge.lock`'s `hash` field now has one meaning

**Landed 2026-09-12.** Design:
`specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md` §0.3 and §4.

## The defect

One field held values from two incompatible domains:

| dep kind | what `hash` was |
|---|---|
| registry | sha256 of the original `.tar.gz` bytes — the registry's published checksum |
| git | sha256 of the canonical archive of the extracted source tree |

Re-hashing a tree can never reproduce a tarball checksum, so **no single
integrity check could cover both** — including the one
`resolver_cas_package.ml` has claimed in a comment since it was written ("On
every build, forge re-hashes each dep's CAS entry and checks it against the
hash recorded in forge.lock. Mismatch → build aborts"), which no caller has ever
performed. Found by reading thirteen real `forge.lock` files rather than the
format comment.

## What landed

- **`hash` is uniformly the canonical-archive hash of the extracted tree**, for
  every dep kind. This is the field an integrity check compares against, and it
  is computable from what is actually on disk.
- **`checksum` is new and optional**: the source artifact's own published
  digest, which today means a registry `.tar.gz` sha256. Provenance — "this is
  the artifact the registry served" — not a tree hash. Absent for git and path
  deps, which publish nothing.
- **`[lockfile] version = 2`** marks the new format.
  `Resolver_lockfile.read_format_version` returns 1 when the section is absent,
  so a caller can tell that a registry `hash` it is reading is in the OLD domain
  and must not be verified against a tree. Format-1 files are still read, so an
  upgrade does not break a build.
- The format comment's `blake3:` examples are corrected to `sha256:`, which is
  what `hash_archive` has always produced (`Digestif.SHA256`).

## Why option B, not the per-domain check

The design doc chose "verify each kind in its own domain" and deferred the
second field on the grounds that it changes the format. That trade looks
different once the registry side is examined: a registry dep's tarball is
downloaded to a temp file and **deleted after extraction**, so its recorded
checksum describes bytes that no longer exist anywhere — it is permanently
unverifiable, and a per-domain check would have had nothing to check. Aligning
the field is what makes a uniform check possible at all.

## What is still not done

The verification itself. Nothing yet re-hashes a cached tree and compares it to
`hash`; that is now a straightforward change for every dep kind, which it was
not before. `resolver_cas_package.ml`'s comment therefore remains aspirational
and is left untouched rather than made to look satisfied.

## Verification

`forge/test/test_resolver.ml`'s lockfile round-trip now asserts that the two
values stay distinct through a write/read cycle (a registry entry keeps both a
tree `hash` and a different `checksum`; git and path entries keep `checksum =
None`), and that the format version reads back as 2. Confirmed against a real
`forge deps` run, whose emitted lockfile carries the `[lockfile]` section.
