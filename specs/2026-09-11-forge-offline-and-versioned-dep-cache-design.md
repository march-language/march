# `forge --offline` and a version-aware dependency cache

**Date:** 2026-09-11
**Status:** §2 (version-aware cache) and the §0.3 hash alignment **LANDED
2026-09-12** — see `specs/progress/2026-09-12-version-aware-dep-cache.md` and
`specs/progress/2026-09-12-lockfile-hash-domains-aligned.md`. §3 (`--offline`),
§4's verification and §2.4's tarball cache remain proposed.
**Closes part of:** `specs/todos/2026-07-31-p1-tooling-forge-build-tool.md`, first
bullet ("Vendoring / explicit offline mode … partly mitigated by the CAS cache;
no explicit story"). Vendoring proper (`forge vendor`, an in-tree committed
`vendor/`) is deliberately **out of scope** — see §7.

**Method:** every claim in §0 was checked on 2026-09-11 by opening the cited
file. The todo's own summary ("partly mitigated by the CAS cache") turns out to
overstate what exists; §0 says what is actually there.

---

## 0. What is already true in the tree (verify before building)

- **There is no offline mode, at all.** `grep -rn 'offline\|no_network' forge/
  lib/ bin/` over `.ml` files returns nothing.
- **`--frozen` is not it.** `cmd_build.ml:653-663` rejects a `forge.lock` that
  has drifted from `forge.toml`. It gates *re-resolution*, not the network: a
  frozen build still runs `git clone`.
- **Deps are installed into a NAME-KEYED directory.** All three sites are
  `Filename.concat (cas_deps_dir ()) name` (`cmd_deps.ml:434`, `:484`, `:593`),
  where `cas_deps_dir` is `~/.march/cas/deps` (`cmd_deps.ml:20-22`). Two
  projects wanting different versions of one dep therefore collide on one
  directory. This is the "version-aware" half of the work.
- **The only cache hit today is accidental and silent.**
  `reuse_or_clear_git_dest` (`cmd_deps.ml`) reuses a checkout when the directory
  exists *and* `git_checkout_matches ~url` — i.e. keyed on the remote URL, not
  the requested tag/branch/rev. A different tag of the same URL is reused
  as-is; a different URL triggers `rm -rf` and a re-clone.
- **A content-addressed package store already exists, and is write-only.**
  `resolver_cas_package.ml:130-168` implements `~/.march/cas/packages/<sha256
  hex>/{archive,info.toml}` over a canonical archive. Its only non-test caller
  is `cmd_deps.ml`'s `content_hash` (`:139-144`), which calls `store_directory`
  **for its return value only** — to fill a lockfile field. Nothing ever calls
  `lookup`, so every archive written there is dead weight.
- **`forge.lock` is written but never read to locate a dep.** The lockfile
  records `name`, `version`, `source`, `commit`, `hash` per package
  (`resolver_lockfile.ml:35-41`). The only read anywhere is
  `Resolver_lockfile.read_toolchain` (`cmd_build.ml:686`). **This is the
  keystone: the identity offline mode needs is already being recorded and then
  thrown away.**
- **Two documentation defects, to fix in passing.**
  1. `resolver_cas_package.ml:26-27` claims "On every build, forge re-hashes
     each dep's CAS entry and checks it against the hash recorded in
     forge.lock. Mismatch → build aborts." No caller does this; there is no
     integrity check on a cached dep at all.
  2. `resolver_lockfile.ml:14,21,30` document the hash as `blake3:…`, but
     `hash_archive` (`:113-117`) is `Digestif.SHA256` and `package_dir`
     (`:135-140`) strips a `"sha256:"` prefix. The format comment and its
     examples are wrong.
- **Registry mechanics, in full (§0.2).** They differ from git in ways that
  change this design, so they get their own subsection.
- **Registry deps ARE implemented — via a different function than the one the
  stub arm suggests.** `install_dep`'s `RegistryDep` arm does print "registry
  not yet available, skipping" and write `hash = "pending:<name>"`
  (`cmd_deps.ml:488-496`), but that arm is a fallback: the real path is
  `resolve_registry_deps` (`cmd_deps.ml:302`), which version-solves with
  PubGrub and "download+verify+extract each solved registry package into
  `~/.march/cas/deps/<name>`". **Verified against real lockfiles on this
  machine** (§0.1): `scroll/forge.lock` and `conduit/forge.lock` both carry
  `source = "registry:forge"` entries with a real semver and a real
  `sha256:` hash, not `pending:`. So registry coordinates in §2 are
  load-bearing today, not hypothetical, and registry packages already land in
  the same name-keyed directory the git path uses — so they collide the same
  way.
### 0.2 How a registry dep is actually installed

Read from `cmd_deps.ml:430-467` and `registry_query.ml:63-188` on 2026-09-11.
Four properties matter here, and three of them are hostile to offline use:

1. **The tarball is downloaded to a temp file and then deleted.**
   `Filename.temp_file ("forge_" ^ name ^ "_") ".tar.gz"` (`:435-436`), extracted
   with `tar --strip-components=1`, then `Sys.remove tarball` (`:467`). **Nothing
   caches the original bytes.** The only persistent artifact is the extracted
   tree at `deps/<name>`.
2. **Registry metadata is fetched to a temp file and deleted too**
   (`registry_query.ml:183-188`, `forge_meta_*.json` removed via `Fun.protect`).
   There is **no index or metadata cache of any kind**, so version solving
   *always* requires the network. Offline can therefore never solve a new
   constraint — only follow coordinates already written down (§2.4).
3. **The registry client is compiled, per resolve, by `march`.**
   `registry_query.ml:63-85` writes a `.march` file to a temp path, compiles it
   (native TLS only works compiled), and runs it. That is a local operation and
   offline-safe, but it is also unconditional work before any cache is
   consulted — an offline path must not reach it at all.
4. **Install unconditionally wipes.** `if Sys.file_exists dest then rm -rf dest`
   before extracting (`:448-450`). The git path at least checks the remote URL
   first (`reuse_or_clear_git_dest`); the registry path does not check anything.
   So under today's name-keyed layout, installing `bastion 0.3.1` silently
   destroys a `bastion 0.2.0` another project is using. **The collision §2 fixes
   is worse for registry deps than for git ones.**

### 0.3 The `hash` field holds two incompatible kinds of hash

This one breaks the obvious integrity design, so it is called out separately:

| dep kind | what `forge.lock`'s `hash` is | computed by |
|---|---|---|
| registry | **sha256 of the original `.tar.gz` bytes** — the registry's own published checksum | `"sha256:" ^ expected_cs` (`cmd_deps.ml:463`), after verifying the download against it (`:442-446`) |
| git | **sha256 of the canonical archive of the extracted tree** | `content_hash` → `Resolver_cas_package.store_directory` (`cmd_deps.ml:139-144`) |

> **FIXED 2026-09-12.** `hash` is now uniformly the canonical-archive hash of
> the extracted tree for every dep kind, and a new `checksum` field carries the
> registry's published tarball digest as provenance. A `[lockfile] version = 2`
> marker distinguishes the new format, because a format-1 file's registry
> `hash` is in the old domain and must not be verified against a tree
> (`Resolver_lockfile.read_format_version`). This is option B below, taken
> rather than deferred. §4's per-domain plan is therefore obsolete: one
> uniform check now covers every dep kind, and what remains unimplemented is
> the check itself, not the ability to write one.

One field, two domains. Re-hashing an extracted tree can never reproduce a
tarball checksum: different bytes, different framing. So "re-hash the tree and
compare to `forge.lock`" — the natural integrity check, and the one
`resolver_cas_package.ml:26-27` already falsely claims to perform — **is
unimplementable for registry deps as the lockfile stands**. §4 is written around
this rather than over it.

Worse, because the tarball is deleted (§0.2, item 1), a registry dep's recorded
checksum becomes **permanently unverifiable the moment install finishes**. The
bytes it describes no longer exist anywhere on disk.

### 0.1 What thirteen real lockfiles on this machine actually contain

Read on 2026-09-11 from `~/code/*/forge.lock` (13 files). The format comment is
not the whole truth:

- **3 of 13 are not lockfiles at all.** `db_test`, `conduit_test_app` and
  `blog_app` each contain a single line of **`forge.toml` dependency syntax**:

  ```
  depot = { path = "../depot" }
  ```

  In `db_test` this is present in the repository's initial commit, so it is not
  recent damage. `Resolver_lockfile.read` (`:read`) only fails when the file is
  **absent**; on these it parses no `[[package]]` blocks, never calls
  `flush_package`, and returns `Ok` with **zero entries and no
  `manifest_hash`** — indistinguishable, to a caller, from a project with no
  dependencies. Any offline design that reads this file must treat that state as
  its own outcome (§3.3), or ~23% of real projects silently resolve to "no deps"
  and produce a wall of `Unknown module` errors.
- **`has_drifted` already catches them**, because it maps `Ok (_, None)` to
  `true` (`:has_drifted`). So `--frozen` rejects these three today. That is the
  existing signal `--offline` should reuse rather than re-derive.
- **Coordinates are exactly as §2 needs them.** Git entries carry `commit` and
  no `version`; registry entries carry `version` and no `commit`; path entries
  carry neither. No lockfile needed a coordinate that is not already recorded.
- **Hashes are `sha256:` in every one of the ten well-formed files**, confirming
  the `blake3:` in the format comment is wrong (§0, defect 2).
- **Path-dep sources are spelled inconsistently**: `path:../conduit`
  (relative) in `test_conduit_app` versus
  `path:/Users/80197052/code/depot` (absolute) in `depot_toyapp`. An absolute
  path in a committed lockfile is not portable. Out of scope here, but worth a
  todo of its own.

- **Path deps are not cached.** `dep_to_lib_paths`'s `PathDep` arm resolves
  relative to the project root (`cmd_build.ml:377-380`); nothing is copied. They
  are trivially offline already.
- **Consumption is by directory, not by archive.** `lib_path_env` →
  `collect_transitive_deps` → `dep_to_lib_paths` builds `MARCH_LIB_PATH` out of
  each dep's `lib/` and its subdirectories. So whatever the cache is keyed by,
  the thing handed to the compiler is an **extracted source tree**.

---

## 1. The two decisions this spec records

**`--offline` uses only what is locally available, and WARNS about the rest.**
Not a hard error on first miss (Cargo's behaviour). A project whose missing dep
is never actually imported still builds; a project that needs it gets a warning
naming the dep, plus the downstream failure it predicts. §3 states the exact
contract and the honest cost.

**The dependency cache becomes version-aware.** `deps/<name>` becomes
`deps/<name>/<coord>`, where `<coord>` is the resolved identity from
`forge.lock`. §2 defines `<coord>` per dep kind.

---

## 2. Version-aware cache layout

### 2.1 The coordinate

| dep kind | `<coord>` | why |
|---|---|---|
| `GitTagDep {url; tag}` | resolved commit SHA | a tag can be moved; the commit cannot. `resolve_commit` already computes it and the lockfile already stores it. |
| `GitRevDep {url; rev}` | resolved commit SHA | same field, already exact. |
| `GitBranchDep {url; branch}` | resolved commit SHA | a branch is a moving target *by design*: keying on the commit is what makes an offline build of it deterministic, and what lets two projects pin different points of one branch. |
| `RegistryDep {version}` | the exact resolved semver (`1.4.7`, never a range) | there is no commit; the version is the identity. |
| `PathDep p` | not cached | read in place (§0). |

Every coordinate above is **already recorded in `forge.lock`** (`commit` for git
deps, `version` for registry deps). No new resolution machinery is needed — only
a reader.

Two dep kinds can resolve to the same commit (a tag and a branch pointing at
it). They then share one directory, which is correct: the bytes are identical.

### 2.2 Why coordinate-keyed and not hash-keyed

The purer design keys the extracted tree by the content hash that
`packages/<sha256>` already uses. Rejected as the primary key, for a reason the
tree makes concrete:

- A content hash is only knowable **after** you have the bytes. Offline lookup
  must answer "do I have this dep?" **before** fetching, from the manifest plus
  lockfile alone. A coordinate is derivable without the bytes; a hash is not —
  except from the lockfile, and the lockfile's hashes are not yet trustworthy
  (`pending:<name>` for every registry dep and for any git dep whose directory
  was absent when `content_hash` ran, §0).

So: **coordinate is the address, hash is the integrity check** (§4). Once
registry deps land and hashes are real, `packages/<hash>` can become the
canonical store with `deps/<name>/<coord>` a symlink or a thin index into it;
this layout does not block that and §7 records it.

### 2.4 What a registry dep can be keyed and verified by

Given §0.2, a registry dep offers less to work with than a git dep:

- **Coordinate: the exact resolved version** (`deps/<name>/<version>`), as §2.1
  says. Available from the lockfile without network. Sound, because a registry
  version is immutable by policy — and `retired` is tracked separately in the
  metadata (`rv_retired`), so retirement does not mutate a published version's
  bytes.
- **Artifact: the extracted tree only.** There is no cached tarball to
  re-extract from, so the tree *is* the cache, and a corrupted tree can only be
  repaired by re-downloading.

That last point argues for one addition this spec does recommend:

**Cache the tarball.** Write the downloaded `.tar.gz` to
`~/.march/cas/tarballs/<sha256>.tar.gz` instead of a temp file, keyed by the
checksum that was just verified against the registry. Three things become
possible that are impossible today:
1. Re-extracting a dep offline after its tree is deleted or corrupted.
2. Re-verifying a dep against its *published* checksum at any later time,
   which is what makes the recorded hash meaningful rather than decorative.
3. A `forge vendor` (§7) that vendors the bytes the registry actually served,
   rather than a tree forge reconstructed.

Cost: disk, bounded by the number of distinct dep versions ever installed, with
the same eviction question the rest of the CAS already has and does not answer.
It is additive and can land after §5's step 1, but the design should not pretend
the tree is a sufficient cache when it is not.

### 2.3 Migration off the flat layout

An existing `~/.march/cas/deps/<name>` is a directory where the new code expects
a directory *of* coordinate directories. Handle it explicitly rather than by
accident:

- On first run of the new forge, if `deps/<name>` exists and is a git checkout
  (contains `.git`), resolve its HEAD commit and `mv` it to
  `deps/<name>/<commit>`. That preserves a warm cache across the upgrade, which
  matters because the alternative is every user re-cloning every dep.
- If it exists and is not a git checkout, it cannot be identified: move it to
  `deps/<name>.legacy-<timestamp>` and re-install. Never silently delete a
  directory a user might have hand-placed.
- The migration is a one-shot helper in `cmd_deps.ml`, logged at normal
  verbosity (one line per dep moved), not a hidden side effect.

---

## 3. `--offline`: the contract

`--offline` is a global flag (it belongs on `build`, `check`, `test`, `run`,
`bench`, `deps`, `tree`, `outdated` — every command whose current behaviour can
reach the network). Precisely:

1. **No process that talks to the network is started.** No `git clone`, no `git
   fetch`, no registry query, no `curl`. This is the property worth asserting in
   a test, because it is observable without a network: a sentinel `git` earlier
   on `PATH` that exits non-zero and records its invocation.
2. **Every dep is resolved from `forge.lock` to `deps/<name>/<coord>`.**
   Present → used. Absent → **warned about, and skipped** (left off
   `MARCH_LIB_PATH`).
3. **An unusable lockfile is its own outcome, reported once.** Three distinct
   states, three distinct messages — never N per-dep warnings that bury the
   cause:
   - **Absent.** No coordinate exists for any git or registry dep. One error
     naming that; continue with path deps only.
   - **Present but yielding zero packages and no `manifest_hash`.** This is the
     `forge.toml`-syntax-in-`forge.lock` case, and it is **23% of the real
     lockfiles on this machine** (§0.1). `read` returns `Ok` here, so the code
     must check the shape explicitly: zero entries *and* no manifest hash, on a
     project whose `forge.toml` *does* declare deps, means "this file is not a
     lockfile". One error saying so, naming `forge deps` as the fix. Getting
     this wrong is the single most likely way this feature ships broken.
   - **Parseable.** Use it, subject to the drift check below.
4. **A drifted lockfile warns.** `forge.toml` has changed since `forge deps`
   ran, so the coordinates are stale. `--offline` cannot re-resolve, so it says
   so once and proceeds on the lockfile's coordinates. Reuse
   `Resolver_lockfile.has_drifted`, which already returns `true` for the
   malformed case above — so the *check* is shared and only the *message*
   differs between states.
5. **Registry deps offline can be followed, never solved.** With no metadata
   cache (§0.2), `--offline` cannot evaluate a version constraint, so a registry
   dep is usable offline **only** via its lockfile-recorded exact version. Two
   consequences to state rather than discover:
   - `forge add <pkg>` and `forge outdated` are network-only. Under `--offline`
     they must refuse with one clear message, not fail deep inside a compile of
     the registry client.
   - A registry dep present in `forge.toml` but absent from `forge.lock` cannot
     be resolved offline at all, even if some version of it happens to be in the
     cache — because choosing which cached version satisfies the constraint *is*
     version solving. Warn per §3's contract and skip it; do not guess.
6. **`forge deps --offline`** does not fetch; it reports, per dep, cached or
   missing, and exits non-zero if any is missing. That is the "can I build on a
   plane?" check, and it is the one command where a miss *is* the answer rather
   than a side note.

### The warning text, and the honest cost

A skipped dep does not fail the build. It fails **later**, inside the compiler,
as `Unknown module Foo` — a much worse error than the real one. The warning must
therefore predict it:

```
warning: offline: dependency `depot` (git:…/depot.git @ f7a3b1c) is not in the
         local cache — skipping it.
         If the build fails with "Unknown module Depot", this is why.
         Cached copies live in ~/.march/cas/deps/depot/; run `forge deps`
         with network access to populate it.
```

This is the accepted cost of "warn, don't fail" (§1): a project that does not
import the missing dep builds, and a project that does gets a confusing
compiler error with a warning above it explaining the cause. The mitigation is
that the warning is *specific* — it names the dep, its coordinate, the module
name the compiler will complain about, and the directory to populate.

A rejected alternative, for the record: have the resolver treat the missing
module as a first-class "dep was skipped offline" diagnostic instead of
`Unknown module`. That is better UX and needs the compiler to know why a path is
absent, which means threading offline state from forge into `march`. Out of
scope here; recorded in §7.

---

## 4. Integrity, given two hash domains

Once a cached tree is consumed with no network round trip, the only thing
between the build and a tampered cache is a hash check that **does not exist
today** (§0) and **cannot be written uniformly** (§0.3).

**Do not paper over the two domains with one check.** Two honest options:

**Option A — verify each kind in its own domain (chosen).**
- *Git deps:* re-hash the extracted tree with
  `Resolver_cas_package.hash_directory` and compare to `forge.lock`'s `hash`.
  This works today and makes `resolver_cas_package.ml:26-27` true for the kind
  it was written about.
- *Registry deps:* the recorded hash describes tarball bytes that no longer
  exist, so tree verification is impossible. It becomes possible **only** with
  the tarball cache (§2.4): re-hash the cached `.tar.gz` and compare. Until that
  lands, a registry dep is explicitly **unverified**, and the build says so once
  per run rather than implying coverage it does not have.

**Option B — add a second lockfile field**, so every dep records both a
source-artifact hash and a canonical-tree hash. Uniform and better long-term;
changes the lockfile format, invalidates every existing `forge.lock`, and needs
a compatibility story for a file three of thirteen real projects already have in
a broken state (§0.1). Deferred, and named here so the next person does not
rediscover the need.

Shared rules either way:
- A hash mismatch is an **error**, not a warning: a missing dep breaks loudly,
  but a *wrong* dep produces a build that looks fine. Name the dep, both
  hashes, and the remedy.
- A `pending:` hash cannot be checked. Skip it and report the count once per
  build, so the gap stays visible.
- Hashing every tree on every build has a cost. **Measure it on a project with
  real deps before enabling it unconditionally**; if it is material, gate full
  verification behind `--verify-deps` and CI, and keep something cheap (file
  count plus total size) on the default path.

This section is also where §0's documentation defects get fixed: the
`resolver_cas_package.ml` claim becomes accurate *and scoped to git deps*, and
`resolver_lockfile.ml`'s `blake3:` becomes `sha256:`.

## 5. What gets built, in order

1. **Version-aware cache + migration** (§2). Self-contained, no new flags, and a
   real bug fix on its own (the name collision). Everything else depends on it.
2. **Lockfile → coordinate resolution** (§2.1), used by the normal build path.
   This is the first code to *read* `forge.lock` for anything but the toolchain.
3. **`--offline`** (§3) on top, since by then "locate a dep without fetching" is
   just the normal path with fetching removed.
4. **Integrity check** (§4), plus the two comment fixes.
5. **`forge deps --offline`** as the reporting surface.
6. **Tarball cache** (§2.4), which is what upgrades registry deps from
   "unverified offline" to verifiable and re-extractable.

Steps 1–2 are worth landing alone: they fix the collision and stop the cache
from being URL-keyed, with no user-visible flag.

---

## 6. Test plan

Every case below is network-free, which is what makes it CI-safe.

- **The sentinel-`git` test is the load-bearing one.** Put a `git` on `PATH`
  that exits 1 and appends its argv to a file. Run `forge build --offline` in a
  project with a warm cache: the build must succeed and the file must stay
  empty. **RED control:** drop the `--offline` check in `install_dep` and the
  file gains a `clone` line. This asserts the property in §3.1 directly rather
  than inferring it from a successful build.
- **Version awareness:** two scaffolded projects depending on the same dep name
  at two different tags. Both build; both get their own tree; neither
  reinstalls the other. **RED control:** revert to name-keying and the second
  build wipes the first's directory (observable: the first project's dep tree's
  commit changes).
- **Missing dep warns and does not fail:** a project with a lockfile entry
  whose coordinate dir is absent, and which never imports that module. Build
  succeeds, stderr carries the §3 warning naming the dep.
- **Missing dep that IS imported:** build fails with `Unknown module`, and the
  warning appears above it. Asserted so the bad-but-accepted UX is pinned
  rather than discovered.
- **No lockfile offline:** exactly one error naming the missing lockfile, not
  one warning per dep.
- **Malformed lockfile offline (from real data, §0.1):** write
  `depot = { path = "../depot" }` as the whole of `forge.lock` in a project
  whose `forge.toml` declares deps. Assert exactly one error identifying the
  file as not a lockfile. **RED control:** with the shape check removed, the
  command reports "no dependencies" and exits 0 — the silent failure this case
  exists to prevent. Copy the fixture text verbatim from `db_test/forge.lock`
  rather than inventing it.
- **Registry version awareness (the worst collision, §0.2 item 4):** two
  projects on different versions of one registry dep. Today's `rm -rf`-on-install
  means the second install destroys the first project's tree; after the fix both
  survive. **RED control:** revert to name-keying and the first project's tree
  changes version under it.
- **Registry dep offline, in the lockfile:** builds from
  `deps/<name>/<version>` with no network process started (sentinel again).
- **Registry dep offline, NOT in the lockfile:** warned and skipped even when
  another version of that package is cached — asserting that offline never
  guesses which cached version satisfies a constraint (§3.5).
- **`forge add --offline` / `forge outdated --offline`:** refuse with one clear
  message, and in particular do **not** reach `registry_query`'s compile step
  (assert no `march` subprocess is spawned, the same sentinel technique).
- **Integrity:** corrupt a byte in a cached tree; the build errors naming the
  dep and both hashes. **RED control:** with the check removed, the corrupted
  tree is used and the build succeeds.
- **Migration:** create a flat `deps/<name>` git checkout, run `forge deps`, and
  assert it moved to `deps/<name>/<commit>` with no re-clone (sentinel `git`
  again, permitted to serve `rev-parse` only).
- Harness: `forge/test/test_build_check.ml`'s `with_project` +
  `setup_hermetic_march` (`MARCH_TEST_BIN`), the pattern the existing
  `forge test` cases use.

---

## 7. Out of scope, and why

- **`forge vendor` / in-tree committed `vendor/`.** The other half of the
  todo's first bullet. It is cheap *after* this work (deps are `.march` source
  consumed via `MARCH_LIB_PATH`, so vendoring is a copy plus a path entry) and
  incoherent before it, because a name-keyed cache cannot say *which* version it
  would vendor. It also needs a policy call this spec does not make: whether
  `vendor/` is committed, and whether a vendored tree overrides or merely
  satisfies a lockfile entry.
- **Making `packages/<hash>` the canonical store**, with `deps/` an index into
  it. Blocked on registry deps landing and on hashes no longer being
  `pending:` (§2.2).
- **A first-class "skipped offline" compiler diagnostic** instead of `Unknown
  module` (§3).
- **Registry implementation.** `--offline`'s registry behaviour is specified
  here so it need not be retrofitted, but the registry itself is separate work.
- **`--prefer-offline`** (try cache, fall back to network). Additive; nobody has
  asked; adding it later costs nothing.
- **A second lockfile hash field** (§4, option B) to give registry and git deps
  one uniform verification domain.
- **A registry metadata/index cache**, which is what would let `forge outdated`
  and constraint solving work offline at all (§0.2 item 2). Larger than this
  spec: it needs a staleness policy, and staleness of an index is exactly the
  kind of thing that produces wrong answers quietly.
- **Absolute path-dep sources in committed lockfiles** (§0.1). A separate
  portability defect, found while validating this design; it deserves its own
  todo rather than a rider here.

---

## 8. Acceptance

- `forge build --offline` with a warm cache starts no network process, proven by
  a sentinel `git` that records invocations.
- Two projects depending on different versions of one dep coexist, and neither
  evicts the other.
- A dep missing from the cache offline produces one warning naming the dep, its
  coordinate, and the module name the compiler will report; the build proceeds.
- `forge deps --offline` exits non-zero listing exactly the missing deps.
- A tampered cached **git** tree fails the build, naming expected and actual
  hashes — i.e. `resolver_cas_package.ml`'s longstanding claim becomes true for
  the dep kind it describes. A registry dep reports honestly that it is
  unverified until the tarball cache lands.
- Two projects on different versions of one **registry** package coexist; the
  second install no longer `rm -rf`es the first.
- An existing flat `deps/<name>` checkout survives the upgrade without
  re-cloning.
- A `forge.lock` containing `forge.toml` syntax is reported as not a lockfile,
  rather than resolving to "no dependencies" — checked against the three real
  files in §0.1.
