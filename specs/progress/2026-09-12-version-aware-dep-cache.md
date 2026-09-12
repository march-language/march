# The dependency cache is version-aware: `deps/<name>/<coord>`

**Landed 2026-09-12.** Design:
`specs/2026-09-11-forge-offline-and-versioned-dep-cache-design.md` §2.

## The defect

`~/.march/cas/deps/<name>` was keyed by dependency NAME alone, so every project
on a machine shared one directory per dependency name.

For a git dep that caused thrash: `reuse_or_clear_git_dest` compared only the
remote URL, so the same URL at a *different tag* was reused as-is, and a
different URL triggered `rm -rf` of a directory another project might be
building against.

For a **registry** dep it was outright destructive. `resolve_registry_deps` did
an unconditional `rm -rf` of the destination before extracting, with no check of
any kind, so `forge deps` in a project wanting `bastion 0.3.1` silently deleted
the `bastion 0.2.0` tree another project was building against. The next build
there failed with `Unknown module` for every symbol bastion provided.

## What landed

- **Layout.** An install lives at `deps/<name>/<coord>`: the resolved commit SHA
  for any git dep (a tag or branch can move, a commit cannot), and the exact
  resolved semver for a registry dep. `Cmd_deps.dep_coord_dir`.
- **Git install stages first.** The commit is only knowable after the clone, so
  `clone_git_dep` clones to a staging directory, resolves the commit, then moves
  into place — and if that coordinate is already cached it discards the fresh
  clone and reuses the cached tree, so a concurrent reader is never disturbed.
- **The registry `rm -rf` is now harmless.** It can only ever target one
  version's own directory, never a sibling another project depends on.
- **The lockfile became the locator.** `Project.dep_coords` reads `forge.lock`
  into a name→coordinate table, which `Project.dep_cache_dir` uses to find the
  directory. Before this, nothing read the lockfile except `read_toolchain`: the
  identity a consumer needs was being recorded and thrown away. Wired into
  `Cmd_build.lib_path_env`, `Cmd_test`'s path assembly and `Archive_store`.
- **Fallbacks, in order,** so an upgrade does not break a build: the locked
  coordinate; else a legacy flat install (`deps/<name>` containing `lib/` or
  `forge.toml`); else a container holding exactly ONE coordinate; else `None`.
  A container with several coordinates and no lockfile entry deliberately
  refuses — guessing which version a project wanted is the mistake the layout
  exists to prevent.
- **Migration.** `migrate_flat_install` moves a legacy flat install down to
  `deps/<name>/<commit>`, reading the commit out of the checkout, so a warm
  cache survives the upgrade. One that cannot be identified is moved aside, not
  deleted: a user may have placed it by hand.
- **`update_dep` for a branch dep is now a fresh install**, since a new HEAD is
  a new commit and therefore a new directory. It used to
  `git -C deps/<name> fetch && checkout FETCH_HEAD`, mutating the one shared
  checkout — and would now not even find a git repository there.
- **Removed** `git_checkout_matches` / `reuse_or_clear_git_dest`. Their whole
  job was compensating for name-keying; a comment records why, so nobody
  reaches for the URL-keyed reuse test again.

## Contracts kept separate

`dep_cache_dir` answers "where IS it" (existence-checked, `None` when absent).
`dep_root_dir` answers "where WOULD it be" and still returns a path when nothing
is installed, because `forge audit` / `licenses` / `tree` use it to report
installed-or-not; returning `None` there sent them back to a project-relative
path, which is the exact bug `forge/test/test_dep_dir.ml` exists to prevent.
Conflating the two broke those six tests, which is how it was caught.

## Verification

- `forge/test/test_dep_cache_versions.ml`, six cases on a fake `HOME`, no
  network: two versions coexist and each project's lockfile selects its own; a
  git dep resolves by commit; a legacy flat install still resolves; one cached
  version resolves with no lockfile; several refuse; a path dep contributes no
  coordinate. **RED control:** reverting `dep_cache_dir` to name-keying fails 4
  of the 6, and the 2 that stay green are exactly the ones that do not depend on
  version keying.
- `forge/test/test_regression.ml`'s three URL-keyed-reuse cases were **converted**
  rather than deleted: they now assert the structural property that makes the
  removed guard unnecessary (a git commit and a registry version are never the
  same coordinate, an install is never the container, a flat install is
  detected).
- **End to end with the real installer**, network-free via a local git repo:
  `forge deps` landed the dep at `deps/widget/<commit>` and wrote a format-2
  lockfile; `forge check` resolved `Widget` through the coordinate; with two
  versions cached and a bogus coordinate in the lockfile the build correctly
  refused to guess (`Unknown module Widget`); pointing the lockfile at either
  cached coordinate resolved that one.
- All 15 forge suites green; full march suite green.
