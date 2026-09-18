`[P2]` # forge: explicit offline mode (`--offline`)

Split 2026-09-18 out of `2026-07-31-p1-tooling-forge-build-tool.md` (a `[P1]`
that filed three unrelated features together) per
`specs/2026-09-18-forge-p1-design.md` §1.

**Already designed:** `specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md`.
Its §2 (version-aware dependency cache) and §0.3 (lockfile hash domains) landed
2026-09-12. **What remains is that document's §3 (`--offline`), §4's
verification, and §2.4's tarball cache.** Track the work there; this file only
exists so the item is not lost.

Out of scope here, and in that design: `forge vendor` / an in-tree `vendor/`.
Whether it is wanted at all — air-gapped CI and reproducible archives are the
case for it — is a product call for whoever owns forge's scope.

`[P2]` rather than the original `[P1]`: nothing is broken, and the remaining work
is scheduled rather than blocked.
