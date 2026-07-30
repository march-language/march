# Plan: three forge gaps in registry-dependency handling

**Status:** Implemented 2026-07-30 — B1 and B2 fixed in full; B3 shipped as
option 1 (validate before reuse), with option 2 (source-keyed CAS paths) left
open as follow-up. Kept as the written record of what was wrong and why.
**Repo:** `march-language/march` (forge lives in `forge/` inside the march repo).
**Found:** 2026-07-30, while releasing [scroll](https://github.com/march-language/scroll) 0.1.2 → 0.1.3.

Three independent bugs, all in the handling of `registry = "forge"`
dependencies. They are separable and can land as separate PRs; **B1 is the one
that shipped a broken release** and should go first.

## How they were found (the motivating failure)

scroll is a forge **tool** — it declares `[archive.task.scroll.serve]`, and
`forge scroll.serve` is the only command it exists to provide. scroll 0.1.2
changed its bastion dependency from git to registry:

```toml
bastion = { registry = "forge", version = "0.2.4" }
```

`forge check`, `forge build` and `forge test` all passed. `forge scroll.serve`
failed with `Unknown module Router` / `Middleware` / `Static` — every symbol
bastion provides. The release shipped broken because it was verified with
check/build/test only.

Reproducing the three bugs from a clean CAS (`rm -rf ~/.march/cas/deps/*`):

| forge.toml | `forge deps` fetches | `check`/`test` | `<pkg>.<task>` |
|---|---|---|---|
| `bastion = { git = …, branch = "main" }` | bastion **and** depot | pass | **pass** |
| `bastion = { registry = "forge", version = "0.2.4" }` | bastion only | *fails* — `Module Pool not found` | — |
| registry bastion **+** explicit `depot = { git = … }` | both | pass | **fails** — `Unknown module Router` |

Row 2 is **B2**. Row 3 is **B1**. **B3** surfaced when switching a dep back and
forth between registry and git.

> Caution for whoever picks this up: an early attempt at row 2 appeared to pass
> because a `depot` left over from the git-dep era was still sitting in
> `~/.march/cas/deps/`. **Purge the CAS between every experiment** or you will
> measure the previous run.

---

## B1 — archive tasks silently drop registry deps

**Severity: high.** A package that builds and tests green fails at runtime with
`Unknown module` for everything its registry dependency provides.

### Root cause

`forge/lib/archive_store.ml`, `dep_lib_paths_for_archive`. `Project.dep` has
five constructors (`project.ml:6`) — `RegistryDep`, `GitTagDep`,
`GitBranchDep`, `GitRevDep`, `PathDep`. The archive walk handles path and the
three git forms and then falls off a catch-all:

```ocaml
| Project.PathDep rel_path -> …
| Project.GitTagDep _ | Project.GitBranchDep _ | Project.GitRevDep _ ->
    (match Project.git_dep_lib_path dep_name with …)
| _ -> []            (* ← RegistryDep lands here: contributes NO lib paths *)
```

`forge/lib/cmd_build.ml`'s `dep_to_lib_paths` — the path `check`/`build`/`test`
use — gets it right, and its comment states why the two forms are equivalent:

```ocaml
| Project.GitTagDep _ | Project.GitBranchDep _ | Project.GitRevDep _
| Project.RegistryDep _ ->
    (* Git and registry deps both install under ~/.march/cas/deps/<name>; use
       that dep's lib/ (or its root as a fallback). *)
```

So a registry dep is installed to exactly the same place either way —
`archive_store` just never looks there. Note `dep_lib_paths_for_archive`'s own
docstring claims it "Mirrors cmd_build's `dep_to_lib_paths`". It doesn't; that
comment is what makes the omission look intentional on a skim.

### Fix

Add `| Project.RegistryDep _` to the existing git arm in
`dep_lib_paths_for_archive`, mirroring `cmd_build`. `Project.git_dep_lib_path`
is already name-based (`~/.march/cas/deps/<name>/lib`), so it resolves a
registry install unchanged — verify that rather than assuming.

Then **re-read the whole file for the same pattern.** `archive_store.ml` has
other matches over `Project.dep` (around lines 377 and 402 per the
`lib_path_env` comments); check each for the same missing constructor. A
`| _ -> []` over a five-constructor variant is the shape of this bug — consider
making these matches exhaustive (drop the wildcard, list every constructor) so
a future sixth dep form is a compile error rather than a silent empty path.

### Test

`forge/test/` — model on the existing build/check tests. The regression needs a
**tool**-type package (with `[archive.task.*]`) whose dependency is a
**registry** dep; a library package never exercises this path, and path/git
deps both work, which is why nothing caught it. Assert the archive task's
computed `MARCH_LIB_PATH` contains the dep's lib dir. Prove it RED first —
without the fix the list should come back missing that entry.

---

## B2 — `forge deps` does not fetch a registry package's own dependencies

**Severity: high.** The dependency graph below a registry package is invisible,
so its own imports fail to compile.

### Root cause

`forge/lib/cmd_deps.ml`, two-phase resolution:

- **Phase 1** `bfs_install` installs path/git deps breadth-first. Registry deps
  are deliberately *filtered out* of `fresh` into `reg_acc` so PubGrub can
  version-solve them in one pass. Because they are removed from `fresh`, they
  never reach `results`, and `next_wave` is built only from `results` — so a
  registry package's forge.toml is never read here.
- **Phase 2** `resolve_wave` installs the solved registry set, then discovers
  the next wave — but filters to registry deps only:

```ocaml
List.filter_map (fun (n, d) ->
    match d with
    | Project.RegistryDep { version } -> Some (n, version)
    | _ -> None)          (* ← git/path deps of a registry package: dropped *)
  p.Project.deps
```

So **registry → registry recurses; registry → git/path does not.** The
in-code comment ("a registry dep that itself declares registry deps is picked
up") documents exactly the half that works.

Concretely: bastion is a registry package declaring
`depot = { git = …, branch = "main" }`. depot is never fetched, and bastion's
own `Depot.Middleware` fails with `Module Pool not found`.

Note this is the same *shape* as march#127 (which fixed `cmd_test` resolving
direct-but-not-transitive deps) — a partial graph walk, different walker.

### Fix

After Phase 2 installs a registry package, feed its **non-registry** deps back
into Phase 1's BFS, and its registry deps into Phase 2's fixpoint as today.
The two phases need to alternate to a joint fixpoint rather than run once each:
a git dep of a registry package may itself declare registry deps.

Preserve the existing invariants — they are load-bearing and commented at
length in `collect_transitive_deps`:

- **nearest-wins by dep name** (a direct dep beats one reachable only deeper),
- **breadth-first by depth**, not depth-first — the comment in `cmd_build.ml`
  records a real bug the depth-first version caused,
- `override_deps` must keep excluding every non-registry dep from PubGrub.

Watch for a cycle between the two phases; both already dedup by name
(`visited`, `seen_reg`), so route the new edges through those same tables.

### Test

`forge/test/test_build_check.ml` has the march#127 regression as a model.
Needs a registry package whose forge.toml declares a git dep. If the test
registry cannot host that, assert on the resolver's computed install set from a
synthetic manifest rather than doing real network I/O.

---

## B3 — the CAS keys installs by dep name only, not by source

**Severity: medium** — wrong-source silent reuse, recoverable only by manually
deleting the directory.

### Root cause

`Project.dep_root_dir` (`forge/lib/project.ml:368`) maps every non-path dep to
`~/.march/cas/deps/<dep_name>` with no discriminator for source, URL, branch,
rev or version. `install_dep` in `cmd_deps.ml` then treats *directory exists*
as *correctly installed*:

```ocaml
| Project.GitBranchDep { url; branch } ->
  if Sys.file_exists dest then begin
    Printf.printf "  %s: already installed (branch %s)\n%!" name branch;
    …
```

### Observed

Switching bastion registry → git, `forge deps` printed
`bastion: already installed (branch main)` while `~/.march/cas/deps/bastion`
actually held the **registry tarball extract**, then failed with
`fatal: not a git repository`. The lockfile recorded the git source while the
directory held registry content. Only `rm -rf ~/.march/cas/deps/bastion`
recovered.

The same hazard applies within one source kind: two projects on one machine
depending on the same package at different branches/revs/versions share one
directory, and whichever installs first silently wins.

### Fix — pick one, they trade off

1. **Validate before reuse (smallest).** On the `already installed` path,
   confirm the directory matches the requested source — `.git` present and
   `origin` URL matching for a git dep; a registry marker for a registry dep —
   and re-install on mismatch. Fixes the corruption, not the sharing.
2. **Key the path by source (correct, more invasive).** Make `dep_root_dir`
   include a short hash of the resolved source (`url+rev`, `registry+version`).
   Fixes both, but changes on-disk layout and touches everything that assumes
   `deps/<name>` — including `archive_store.ml`, `Project.git_dep_lib_path`,
   and `cmd_deps.ml`'s Phase-2 `Filename.concat (cas_deps_dir ()) e.name`.
   Needs a migration story for existing CAS dirs.

Recommend **(1)** now and file **(2)** separately — (2) is a layout change that
should not ride along with a correctness fix.

### Test

Unit-level: install a dep from source A, rewrite the manifest to source B,
re-resolve, assert the directory holds B (or that a clear error is raised) —
not a stale A with a success message.

---

## Suggested order

1. **B1** — one arm in an existing match; unblocks tool packages using registry
   deps. Also audit the sibling matches in `archive_store.ml`.
2. **B2** — the real design work (joint fixpoint across both phases).
3. **B3** option 1; file option 2 as follow-up.

## Verification for any of these

`dune build` then the suites: `test/run_eval.exe`, `run_compiler.exe`,
`run_codegen.exe`, `run_snapshots.exe`, `run_stdlib.exe`, plus forge's own
`forge/test/`. Expect one **pre-existing** `MARCH_SANITIZE` failure in
`run_stdlib` on macOS — it is environmental (a trivial unrelated
`clang -fsanitize=address` binary hangs identically); that test's own message
tells you to check exactly that before blaming a change.

End-to-end check that B1 and B2 are actually fixed, using scroll:

```bash
rm -rf ~/.march/cas/deps/bastion ~/.march/cas/deps/depot   # MUST purge
# in a scroll checkout, set: bastion = { registry = "forge", version = "0.2.4" }
# and remove any explicit depot line
forge deps          # must fetch bastion AND depot (B2)
forge test          # 228/228
forge scroll.serve  # must serve on :4040 with no `Unknown module` (B1)
```

scroll `main` currently pins bastion by git rev as the workaround
(`36e85e04…`, which is bastion 0.2.4) with an inline comment pointing back at
B1. Once B1 and B2 land, that can become a plain registry dep again — see
scroll's CHANGELOG 0.1.3.

## Toolchain gotchas that will cost time otherwise

- **The CAS artifact cache is keyed on source hash only, not compiler
  version**, so a stale binary survives a compiler rebuild. After every forge
  or compiler change:
  `rm -rf ~/.march/cas/artifacts ~/.march/cas/artifacts-v2 <project>/.march/cas`
- **`forge` does not use `march`/`forge` from `$PATH`.** It resolves through
  `~/.march/current` → `~/.march/versions/<tag>/bin/`, and `make install` only
  updates `~/.opam/march/bin/`. To make a change live for `forge`-driven runs:

  ```bash
  cd /path/to/march && make install
  cp _build/default/bin/main.exe        ~/.march/versions/local-main/bin/march
  cp _build/default/forge/bin/main.exe  ~/.march/versions/local-main/bin/forge
  cp -R runtime/. ~/.march/versions/local-main/runtime/
  md5 -q _build/default/forge/bin/main.exe ~/.march/versions/local-main/bin/forge
  ```

  The `forge` binary is the one that matters for all three of these bugs.
