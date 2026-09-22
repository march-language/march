# forge: explicit offline mode (`--offline`), integrity check, tarball cache

**Landed 2026-09-22.** Design:
`specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md` §3
(`--offline`), §4 (integrity) and §2.4 (tarball cache). This closes the todo
filed as `specs/todos/2026-07-31-forge-offline-mode.md` (split on 2026-09-18
out of the old forge P1 todo). The design's §2 (version-aware cache) and §0.3
(lockfile hash domains) had already landed on 2026-09-12. Both were checked
in `forge/lib/` before this work started: `Cmd_deps.dep_coord_dir`,
`Project.dep_coords` / `dep_cache_dir`, the format-2 lockfile with a separate
`checksum`.

**Still out of scope:** `forge vendor` and an in-tree `vendor/`. Whether they
are wanted is a product call (design §7).

## What landed

- **One choke point for the network: `forge/lib/net_gate.ml`.** Every
  operation that can reach the network asks `Net_gate.permit` right before it
  starts its process, or runs through `Net_gate.command`. That covers the git
  dependency clone, the registry metadata and tarball fetches, compiling the
  registry client, toolchain `curl` downloads, `npm install` for `[js_deps]`,
  the archive/install clones, and publish/retire. Offline, `permit` refuses
  with a message naming the operation and the command that fills the cache.
  `Cmd_deps` used to carry private copies of the registry client compile,
  fetch and JSON parsing. They were removed so the gated `Registry_query`
  versions are the only path. A test hook, `Net_gate.on_permit`, fails a test
  if offline code is ever granted access.
- **The global flag.** `--offline` is accepted by every command, in any
  position before a bare `--`. `main.ml` strips it from argv before cmdliner
  and the pre-dispatch see it (`Net_gate.extract_flag`), then exports
  `FORGE_OFFLINE=1` so archive tasks and external `forge-<cmd>` binaries
  inherit it. Precedence: the design specifies none. Offline is on if the flag
  is given OR `FORGE_OFFLINE` is truthy (`0`/`false`/`no`/`off`/empty count as
  unset). There is no config-file setting, and nothing turns offline off, so
  the two sources only ever add the restriction. Documented in `forge --help`
  (OFFLINE MODE) and `docs/tooling.md`.
- **Resolution comes from `forge.lock` only** (§3.2, §3.5).
  `Project.dep_cache_dir` offline uses only the lockfile coordinate. The
  legacy flat install and single-cached-version fallbacks are off, so offline
  never picks a version the lockfile does not name.
- **Offline preflight** (`Cmd_build.offline_preflight`, run by build, check,
  run, test and bench; logic in `forge/lib/offline_deps.ml`):
  - an absent lockfile, or one that is not a lockfile (zero packages and no
    manifest hash, i.e. `forge.toml` syntax), is reported ONCE, and only
    path deps are used;
  - drift gets one warning;
  - a dep that is not locked or not cached gets the design's §3 warning,
    which names the dep, its source and coordinate, the `Unknown module` it
    predicts, and the cache directory;
  - every cached tree about to be used is re-hashed against the lockfile's
    `hash`, and a mismatch is an error naming the dep and both hashes (§4).
    A `pending:` hash, or a registry `hash` in a format-1 lockfile (a
    different domain), is reported once as unverified.
- **`forge deps --offline`** (§3.6, `Cmd_deps.run_offline`) fetches and
  writes nothing. It prints one line per dependency (cached/verified,
  missing, corrupt, restored) and exits non-zero on any miss or mismatch.
- **`forge add` (registry or git) and `forge outdated` refuse offline**
  before forge.toml is touched and before any `march` subprocess.
  `forge add --path` still works.
- **Tarball cache** (§2.4, `forge/lib/tarball_cache.ml`):
  `~/.march/cas/tarballs/<sha256>.tar.gz`, keyed by the registry's published
  checksum. `store` refuses bytes that do not hash to the key and writes
  atomically (temp file in the cache dir, then rename). `lookup` re-hashes on
  every read, and a mismatching entry is reported as `Corrupt`, removed and
  never returned. The online registry install now reuses a cached tarball
  instead of downloading, and adds new downloads to the cache only after they
  verify. Offline (build preflight and `forge deps --offline`), a registry
  dep whose tree is gone but whose tarball is cached is re-extracted to a
  staging dir, checked against the lockfile tree hash, then renamed into
  place.
- **Two fixes found on the way**, both leftovers of the 2026-09-12
  version-keyed layout:
  - `forge deps` looked for an installed registry package's own forge.toml at
    the flat `deps/<name>`, so it never discovered that package's
    dependencies. It now uses `deps/<name>/<version>`.
  - `Cmd_build.collect_transitive_deps` walked without the lockfile
    coordinates, so a dep with several cached versions was never descended
    into and its own deps were dropped. It now takes `?coords`, and both
    `lib_path_env` and `Cmd_test.project_env` pass them.
- Comments corrected: `resolver_cas_package.ml`'s long-standing "every build
  re-hashes" claim now says what is true (offline builds and
  `forge deps --offline` check the tree; online builds do not yet), and
  `resolver_lockfile.ml`'s "checksum is not verifiable (tarball not cached)"
  note is updated.

## Verification

New suite `forge/test/test_offline.ml` (21 cases). Its dune rule passes the
just-built `forge` and `march` binaries. The end-to-end cases run the real
forge under a private HOME with sentinel `git`/`curl`/`npm` (and, for
add/outdated, `march`) first on PATH. Each sentinel appends its argv to a log
and exits 1, and `FORGE_REGISTRY` points at a closed local port. "No network
process started" is asserted from that log. Warm caches are populated the real
way: `forge deps` with a real git against a local repository, then the offline
command runs with the sentinel.

Cases: argv stripping; env-var values and precedence; permit refuses offline;
the git install and the registry-client compile are refused offline, with the
hook proving no access was granted; the tarball cache round trip (no temp
file left), refusal of wrong bytes, and detection plus removal of a corrupted
entry; lockfile state classification from the verbatim `db_test/forge.lock`
text; warm cache (build, deps and check offline succeed with an empty sentinel
log); `deps --offline` with a missing dep (non-zero, no clone); missing
unimported dep (warns, succeeds); missing imported dep (warning, then
`Unknown module`); no lockfile (exactly one error); forge.toml-syntax lockfile
(exactly one error, never "no dependencies"); registry dep in the lockfile
builds offline; registry dep not locked is skipped although another version is
cached; the transitive walk follows the locked version; add/outdated refuse
with forge.toml untouched; a tampered cached tree fails with both hashes; the
tarball restore works, and a corrupted cached tarball is discarded and not
extracted.

**Red control 1: the pre-change forge.** The same test binary was run with
`FORGE_TEST_BIN` pointed at a forge built from `origin/main` (`bfb22f1ec`) in
a separate worktree. All 11 end-to-end cases that existed at the time FAILED
(the transitive-walk case was added later and was covered by red control 3).
Two representative failures:
`forge: unknown option '--offline'` and, for the env-var form,

    FAIL no network process was started (sentinel log)
       Expected: `""'
       Received: `"git clone --depth 1 --branch v1.0.0 file:///…/up-widget-… …/home/.march/cas/deps/.staging-widget-10376\n"'

**Red control 2: one perturbation per mechanism**, each applied, rebuilt, run
and restored (`build=0` confirmed for each, so the perturbation was really
compiled in):
- remove the not-a-lockfile shape check: the lockfile-state case and the
  malformed-lockfile e2e fail;
- `assess ~verify:false`: the tampered-tree case fails;
- `Tarball_cache.lookup` skips its re-hash: the corruption unit test and the
  tarball e2e fail;
- remove the offline-strict branch of `dep_cache_dir`: the "not locked,
  cached version not guessed" case fails;
- make `Net_gate.is_offline` always false: the gate cases and the warm-cache
  e2e fail.

**Red control 3: the transitive-walk fix.** Dropping `?coords` from the walk
(with `ignore coords` so it still compiles) fails "transitive walk follows
the locked version".

**Integrity cost** (§4 asks for a measurement before an unconditional check):
`forge deps --offline` over a 126-file, 1.8 MB tree (a copy of the stdlib)
took 0.01 s with the re-hash and 0.00 s with a `pending:` hash. That is
negligible, so the offline path always verifies and no `--verify-deps` gate
was added.

`dune build --root . @forge/test/runtest`: exit 0, all 17 forge suites green.
`scripts/check-docs.sh`: exit 0.

## Not covered / follow-ups

- **Online builds still do not verify cached trees.** The measurement above
  says it would be cheap. Filed as
  `specs/todos/2026-09-22-forge-verify-dep-trees-online.md`.
- The online registry path through the tarball cache (download, verify,
  cache, reuse on reinstall) has no end-to-end test, because there is no local
  registry fixture. It is covered only by the `Tarball_cache` unit tests and
  the offline restore e2e.
- `forge vendor`: out of scope (see above).
