# `[P2]` A CAS cache hit for a `--compile-so` build copies the `.so` without its sidecars

**Found** 2026-09-24 (build step 8). `bin/main.ml`'s two artifact-cache hits
(`compiled <out> (cached)`) copy the cached binary to `-o` and stop. For a
`--compile --compile-so --hot-reload P` build the FIRST compile also writes
`<out>.so.hcr_manifest` and `<out>.so.schemas.json` next to the output; a later
build of the same source with the same flags into a different `-o` (or after the
sidecars were deleted) restores only the `.so`, so `forge deploy hot` and
`forge test --upgrade-from` find no manifest. `forge/lib/upgrade_test.ml` works
around it by running each patch build from a fresh working directory (the store is
`<cwd>/.march/cas`), at the cost of a full recompile per run.

**Fix.** Store the sidecars in the CAS with the artifact (or under the same key
with a suffix) and restore them on a hit; or skip the cache when `--compile-so`
is set. Test: compile a `.so` twice into two output paths and assert both have a
manifest.

---

## Fixed 2026-09-25

`lib/cas/cas.ml` stores a `--compile-so` build's sidecars (`.hcr_manifest`,
`.schemas.json`) next to the artifact blob, with a `<blob>.sidecars` list of what
was stored. `bin/main.ml` stores them under both cache keys once they are written,
and the source-level early hit (the one that `exit 0`s before the code that writes
them) restores them, removing a stale sidecar at the destination that the cached
build did not produce. A `--compile-so` hit whose entry has no sidecar record (cached
before this fix) is treated as a miss. The post-TIR hit already rewrote them.

Test: `test/test_stdlib_suite.ml` "HCR: a CAS hit for a --compile-so build restores
.hcr_manifest and .schemas.json" compiles the same source twice from one working
directory into `a.so` and `b.so`, asserts the second is `(cached)` and both sidecars
are byte-identical. With the restore skipped it fails on `the cache hit restored
.hcr_manifest`. `forge/lib/upgrade_test.ml` still builds each version from a fresh
working directory, now only so the two versions never share a store.
