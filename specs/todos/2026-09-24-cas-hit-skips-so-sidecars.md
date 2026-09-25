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
