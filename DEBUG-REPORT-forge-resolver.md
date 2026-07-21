# Debug report: deterministic multi-package module-resolution failure (bastion + depot + march_doc)

Branch: `multi-package-resolution` (based on main @ 81938ed4)
Commit: `78a7b10d fix(forge): direct dep must outrank same-named transitive dep on MARCH_LIB_PATH`

## TL;DR

The bug is **not** in the compiler's typecheck / name resolution. It is in
**forge's dependency-graph traversal** (`forge/lib/cmd_build.ml`,
`collect_transitive_deps`). When a project depends **directly** on `depot`
(path dep) *and also* on `bastion`, and `bastion` itself depends on `depot`
via a **git** dep, forge's depth-first walk claimed bastion's git-`depot`
before it ever reached the project's own direct path-`depot`. The git dep
resolves to the (empty) CAS install dir `~/.march/cas/deps/depot`, contributing
**no lib path**; the project's real path-`depot` was then dropped as
"already visited". Result: **depot's lib was entirely absent from
MARCH_LIB_PATH**, so `import Depot`, the wire modules
`Connection`/`Db`/`Pool`/`Message`, and their constructors (`ParamText`, …)
were all unresolvable in any consumer that also depended on bastion.

## Reproduction

`forge build` in the repro dir (`.../scratchpad/depot-repro`, deps
bastion + depot + march_doc as clean path checkouts) failed deterministically
(3/3 runs identical), with errors of the form:

```
lib/depotrepro.march:6:2: error: Module `Connection` not found (looked for `connection.march` ...)
lib/depotrepro.march:7:2: error: Module `Db` not found ...
I don't know a constructor called `ParamText`.  Did you mean: `PathDep` — from type `Dep` (bastion)
```

## Root-cause investigation (systematic)

1. **Located the real error source.** The failing messages
   ("Module `X` not found (looked for `x.march` in the source directory)")
   come from `lib/resolver/resolver.ml:210`, i.e. `find_file` failing to locate
   a module file on the search path — a **module-discovery** failure, not a
   typecheck failure. The `ParamText` constructor error is *downstream*: with
   depot's files off the path, its constructors never enter the env, and the
   hint engine only sees bastion's constructors (hence "Did you mean `PathDep`",
   a bastion type) — matching established fact #7.

2. **Forge assembles MARCH_LIB_PATH** (`cmd_build.ml:lib_path_env` →
   `collect_transitive_deps` → `dep_to_lib_paths`). A git/registry dep resolves
   via `Project.git_dep_lib_path`, which reads `~/.march/cas/deps/<name>` — and
   **the CAS deps dir was empty**, so a git `depot` contributes `[]`.

3. **Confirmed the traversal-order mechanism empirically** (ruling out guesses):
   - Baseline trio: **5–9 errors** (file-set dependent), deterministic.
   - **bastion + depot** (2 deps) *also* fails (5 errors) — i.e. the
     "any two work" framing was environment-specific; the true trigger is simply
     "a consumer that path-deps depot AND depends on bastion (which git-deps
     depot)".
   - **depot + march_doc** (no bastion): **0 errors**.
   - Patching bastion's `forge.toml` so its `depot` dep is a *path* dep (so
     `depot` resolves identically regardless of traversal order): the trio and
     bastion+depot both drop to **0 resolution errors**. This isolates the cause
     to the git-vs-path, direct-vs-transitive dep-name collision.

4. **Read `collect_transitive_deps`.** It was `List.concat_map` **depth-first**:
   for `deps = [bastion; depot]` it added bastion, *immediately recursed* into
   bastion's own deps (git `depot` → marked visited, empty CAS → no path), then
   reached the top-level path `depot` and skipped it as already-visited. The doc
   comment claimed "nearest-wins (a direct dep shadows the same name pulled in
   transitively)" — but the implementation was **first-visited-in-a-DFS wins**,
   which lets a *transitive* dep of an earlier sibling beat a *direct* dep.

## How this explains every established fact

- **Deterministic on main:** dep-graph traversal order is deterministic; the
  wrong `depot` (or no `depot`) is chosen every run.
- **Error-count sensitivity to file set / CAS state:** the manifestation depends
  on *what the git `depot` resolved to*. With an empty CAS → "module not found"
  for every depot module. With a *stale* CAS/lockfile copy (fact #6 mentions a
  since-deleted `bastion/forge.lock` + populated CAS) → a **different, older**
  set of depot files on the path, so *which* symbols still resolve depends on
  the file-set overlap — exactly the observed error-count sensitivity, and why
  the task author saw "any two work / trio breaks" under their earlier
  environment while I now see bastion+depot also break with an empty CAS.
- **Flappy pre-d95fe942, deterministic post-d95fe942:** d95fe942 removed a
  *separate* typecheck nondeterminism (order-dependent bare cross-module ctor
  resolution). It did **not** cause this bug and its code was not the fix site;
  it merely removed the noise that previously let the wrong/partial module set
  sometimes accidentally typecheck. Once typecheck became order-independent, the
  underlying forge dep-shadowing failure became deterministic. This is why
  "start from d95fe942" pointed at typecheck yet the true fix is in forge.

## Fix

`forge/lib/cmd_build.ml` — rewrite `collect_transitive_deps` to traverse
**breadth-first by dependency depth**. Every dep at one depth is claimed
(marked in `visited`) **before** any deeper dep is examined, so a **direct**
dep of the root always shadows the same name pulled in transitively — the
documented nearest-wins semantics, now actually implemented. Dedup is still by
dep name; result order is depth-major (direct deps first), deterministic.

Correct semantics achieved: a package's own direct deps resolve to *their*
libs regardless of what a sibling drags in transitively; `import Depot`
resolves to depot's anchor module; depot's unqualified constructors resolve.

## Regression test

`forge/test/test_build_check.ml` ::
`test_direct_path_dep_beats_transitive_git_dep` — minimal 3-project fixture:
A path-deps `[midb; leafc]`; `midb` git-deps `leafc` (unresolvable, empty CAS);
A's own code calls `Leaf.value()`. Asserts `forge check` succeeds (A's direct
path `leafc` wins). **Verified the test genuinely catches the bug**: reverting
`collect_transitive_deps` to the old depth-first code makes this test FAIL;
with the fix it passes.

## Verification evidence

**(a) Repro — 3 consecutive runs, resolution/constructor errors:**
`depot-repro` → `0 / 0 / 0`. A `needs`-complete variant of the entry
(`t-clean`, trio deps) → **0 resolution errors**; `ParamText` now resolves as a
known constructor (only a benign non-exhaustive-match warning remains).
`bastion + depot` two-dep case → `0`.

**(b) march test suite (`dune runtest --root .`):** no NEW failures. My change
is confined to `forge/lib/cmd_build.ml` + `forge/test`; the only test in the
touched suite that fails — `forge check :: "qualified-call cycle does not break
bare ctor ordering"` (test 8) — was verified to fail **identically with the old,
unmodified `collect_transitive_deps`** (it exercises a march typecheck
limitation, independent of dep resolution). All other observed failures are in
subsystems my forge-only change cannot link into (stdlib doctests:
Path.assert_no_traversal / Cluster.* / Parallel.psum_float; LSP code-action
tests; the known `test_scheduler*` wedge) — the pre-existing set the task
flagged. My new test passes.

**(c) Real app (`forgepm`, deps bastion+depot+march_doc, pristine):**
**215 errors → 5.** The eliminated 210 were the entire depot-not-found /
constructor-not-found class. The remaining **5 are a genuine, unrelated
bastion↔depot source drift**, not the resolution bug: `bastion/lib/view/form.march`
does `import Gate` and uses a bare `Gate` type, but current depot defines it as
`mod Depot.Gate` (in `lib/data/depot_gate.march`) — there is no top-level `Gate`
module to import. depot builds standalone with 0 errors; these 5 errors were
previously *masked* by the 215 depot-absent errors and are outside the scope of
this fix (they require bastion to update its `import Gate` → `import Depot.Gate`).

## Concern

The task's success bar for the real app was "215 → 0". The fix delivers
"215 → 5", and the residual 5 are a pre-existing bastion/depot API mismatch
(`import Gate` vs `mod Depot.Gate`) that is independent of the module-resolution
bug and should be fixed in bastion's source, not the compiler/forge.
