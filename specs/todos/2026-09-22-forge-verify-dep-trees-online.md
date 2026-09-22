`[P3]` # forge: verify cached dependency trees on online builds too

Filed 2026-09-22 while landing `forge --offline`
(`specs/progress/2026-09-22-forge-offline-mode.md`).

Offline builds (and `forge deps --offline`) re-hash every cached git/registry
dependency tree against `forge.lock`'s `hash` and fail on a mismatch
(`Offline_deps.verify_tree`, called from `Cmd_build.offline_preflight`). Online
builds consume the same cached trees with no network round trip and do NOT
check them. A tampered or corrupted tree under `~/.march/cas/deps/` therefore
builds quietly unless you pass `--offline`.

Design §4 asked for a measurement before enabling the check unconditionally.
The measurement is ~0.01 s for a 126-file, 1.8 MB tree, so cost is not the
obstacle. What remains:

- run the same check on the online path. The simplest version is to make
  `offline_preflight`'s integrity half unconditional and keep the
  offline-only warnings offline;
- decide what an online mismatch should do. Offline it is an error. Online,
  `forge deps` could reinstall instead;
- a test that tampers a tree and runs `forge build` without `--offline`.
