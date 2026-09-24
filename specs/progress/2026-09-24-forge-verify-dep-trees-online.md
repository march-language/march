# forge: verify cached dependency trees on online builds too

**Landed 2026-09-24.** Closes the todo filed 2026-09-22 while landing
`forge --offline` (`specs/progress/2026-09-22-forge-offline-mode.md`). Design:
`specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md` §4.

## The problem (as filed)

Offline builds (and `forge deps --offline`) re-hashed every cached git/registry
dependency tree against `forge.lock`'s `hash` and failed on a mismatch
(`Offline_deps.verify_tree`, called from what was `Cmd_build.offline_preflight`).
Online builds used the same cached trees with no network round trip and did NOT
check them, so a tampered or corrupted tree under `~/.march/cas/deps/` built
quietly unless you passed `--offline`. Design §4 asked for a measurement
before an unconditional check. It measured ~0.01 s for a 126-file, 1.8 MB tree,
so cost was not the obstacle.

## What landed

- **One preflight for both modes: `Cmd_build.deps_preflight`** (renamed from
  `offline_preflight`). Build, check, run, test and bench call it once per
  invocation, before `MARCH_LIB_PATH` is assembled, never per file. `forge test`
  and `forge bench` return early when there is nothing to run, and in that case
  the preflight does not run either. Offline, the body is the old one,
  unchanged. Online, it calls the new `online_verify`.
- **Online behaviour on a mismatch: re-fetch, re-verify, swap in.** The network
  is available, so `online_verify` does not fail the build. It calls
  `Dep_refetch.refetch` (new, `forge/lib/dep_refetch.ml`):
  - a git dep is cloned again at the locked commit (a full clone plus
    `checkout`, through `Net_gate.command`);
  - a registry dep is re-extracted from the tarball cache if that holds an
    intact copy, with no network. Otherwise the tarball is downloaded, checked
    against the lockfile's `checksum`, and cached first;
  - the fresh copy is staged next to the cached tree and re-hashed against
    `forge.lock`. Only if it matches is it swapped in: the old tree is renamed
    aside, the new one renamed into place, and the old one deleted. A one-line
    ``note: dependency `x` (...)`` goes to stderr;
  - if the fresh copy ALSO mismatches, the cache was not the problem:
    `forge.lock` or the upstream source changed. That is an error naming the
    dependency, the lockfile hash, the fresh copy's hash and the cached tree's
    hash, and it tells the user to run `forge deps` to re-lock if the upstream
    change is expected. The cached tree is left alone.
  - After any replacement the closure is walked again, because the restored
    tree's `forge.toml` may name deps the tampered one did not. Each tree is
    re-fetched at most once, which bounds the loop.
- **The offline-only output stays offline.** The online path prints nothing
  except the replacement note or the error. It does not report an unusable or
  drifted lockfile, a missing or unlocked dep, or an unverifiable (`pending:` or
  format-1 registry) hash. Online resolution has its own fallbacks for those,
  and they were never errors online. Deps without a lockfile coordinate are not
  checked: there is no recorded hash to check them against.
- **`forge deps` no longer launders a tampered tree** (found while testing
  this). `Cmd_deps.clone_git_dep` clones to staging, and when the commit's
  directory already existed it kept the cached tree and then wrote
  `content_hash dest` into `forge.lock`. That wrote the TAMPERED tree's hash, so
  every later check (online or offline) passed against the tampered copy. It
  now compares the cached tree with the fresh clone, and on a difference
  replaces the cached tree with the clone (`Dep_refetch.swap_in`) and says so.
  Registry installs already `rm -rf` and re-extracted.
- `Cmd_deps.cached_or_download` / `download_url` moved to `Dep_refetch`
  (Cmd_deps depends on Cmd_build, so Cmd_build cannot call into it). Cmd_deps
  keeps aliases. The expected checksum is now normalised, so a lockfile
  `sha256:` spelling compares correctly.
- The offline mismatch message no longer tells the user to delete the tree by
  hand. It says an online run re-fetches it.
- Comments in `resolver_cas_package.ml` and `offline_deps.ml`, the `forge --help`
  OFFLINE MODE text and `docs/tooling.md` (Lock File, Offline Builds) describe
  the new behaviour.

## Verification

Seven new end-to-end cases in `forge/test/test_offline.ml` ("online
integrity"). They reuse the offline suite's fixtures: a private HOME, a local
git upstream, a real `forge deps` to fill the cache, and sentinel `git`/`curl`/
`npm` that log and fail.
1. clean tree, online build: succeeds, prints no note or integrity text, and
   the sentinel log is empty (verifying starts no network process);
2. tampered git tree (the module's `answer` renamed so a build against it
   FAILS), online `forge build`: succeeds, prints exactly one note, the tree
   hashes to the lockfile value again, no staging or aside dirs are left, and a
   second build is silent with no network;
3. the same for `forge check`, `forge test` and `forge bench`: each prints
   exactly one note (once per invocation) and restores the tree;
4. lockfile hash pointed at a value no tree has: the build fails, and the error
   says the fresh copy mismatches too and names both the lockfile hash and the
   fresh copy's hash. The cached tree is untouched;
5. offline tamper: still an error, with no re-fetch note and no network;
6. tampered registry tree with its tarball in the tarball cache: the online build
   restores it from the tarball with no network process;
7. `forge deps` online over a tampered tree: `forge.lock` keeps the true hash,
   and the tree is replaced by the clone.

**Red on origin/main** (`12e9f647b`). The lib sources were swapped back to
origin/main by file copy, forge was rebuilt (build exit 0), and the new cases
ran against it. Cases 2, 3, 4, 6 and 7 FAILED; 1 and 5 passed, as expected
for guards of unchanged behaviour. Case 2 failed with the tampered tree used
as-is: ``error: Unknown module `Widget` `` / `typecheck failed`. Case 7 failed
with `forge.lock keeps the true hash`: expected `sha256:fb9a…9b66`, got
`sha256:ea6e…9234`, the tampered tree's hash re-locked. Sources were then
restored.

`dune build --root . @forge/test/runtest`: exit 0, all 21 forge test
executables report success. test_offline now runs 28 cases.

## Not covered

- The registry re-fetch path that DOWNLOADS (tarball not cached) has no
  end-to-end test. There is still no local registry fixture (the same gap the
  offline-mode entry noted). It reuses `cached_or_download`, the function
  `forge deps` uses.
- A tree swap is not atomic against a concurrent reader in another process.
  There is a short window between the two renames where the directory is
  absent. That only happens on a tree that was already corrupt.
