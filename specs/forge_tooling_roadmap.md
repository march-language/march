# Forge Tooling Roadmap

Six registry-independent features that round out forge as a comprehensive build / package / version tool: **`forge watch`**, **`forge bench`**, **release ergonomics** (`forge version` / `forge release`), **`forge licenses` + `--frozen`**, **shell completions + external subcommands**, and **workspaces**.

**Status: Proposed — not yet implemented.** This is a design + testing + documentation plan to be reviewed before any work starts. Each feature is independently shippable; a suggested order is at the end. The big package-management gaps that need a registry *server* (`forge publish` push, `outdated`, `audit`, `yank`, auth) are deliberately out of scope here — see [forge_version_manager.md § Gaps & Roadmap](forge_version_manager.md).

## Conventions used in this spec

Every feature section has the same shape:

- **Motivation** — why it earns its place.
- **CLI surface** — exact commands/flags.
- **Behavior** — what it does, edge cases.
- **Implementation** — concrete modules/functions in `forge/lib` + wiring in `forge/bin/main.ml`.
- **Testing plan** — *unit* (pure logic extracted into a testable function, added to `forge/test/test_forge.ml` as a new alcotest group) + *e2e* (run the built `forge` binary against a throwaway project under an isolated dir, the pattern already used for the toolchain features).
- **Documentation** — README section, `docs/` page if warranted, and the mandatory `specs/todos.md` (move to Done) + `specs/progress.md` (Current State entry) updates per `CLAUDE.md`.

**Shared engineering rules** (apply to all six):

- **Extract a pure core, unit-test it, e2e the IO.** Network/filesystem/shell orchestration is verified e2e; the decision logic (parsing, selection, diffing, formatting) is a pure function with alcotest cases. This mirrors how `Toolchain.valid_tag`/`default_tag`/`classify_remote`, `Deptree`, and the lockfile round-trip are already tested.
- **Quote every interpolated path** passed to `Sys.command` (`Filename.quote`) — see the injection fix in `cmd_build`/`cmd_run`.
- **Commands** are registered in `forge/bin/main.ml` (`Cmd.v`/`Cmd.group`, added to the `cmds` list), returning `(unit, string) result` through the existing `handle`.
- **Run tests** with `dune build --root .` / `dune runtest --root .` in the worktree.

---

## 1. `forge watch`

**Status: ✅ Implemented (2026-06-14)** — `forge/lib/watcher.ml` (pure `changed`/`snapshot_of`, 5 unit tests) + `forge/lib/cmd_watch.ml` + `watch_cmd` in `main.ml`. Polling watcher over `lib/ src/ test/ config/` + `forge.toml`, reruns `build`/`test`/`run`, never exits on failure. Verified e2e (touch → rerun).

**Motivation.** The highest-frequency dev loop is *edit → build/test → read output*. A watch mode that rebuilds (or re-tests/re-runs) on save removes the manual round-trip — the single biggest day-to-day DX win, and fully self-contained (no registry, no network).

**CLI surface.**
```
forge watch [build|test|run]      # default: build
forge watch test --filter foo
forge watch --interval 300        # poll interval ms (default 300)
forge watch --clear               # clear the screen before each run
```

**Behavior.**
- Collects the watched file set: every `.march` under `lib/`, `src/`, `test/`, plus `forge.toml` and `config/` (reuse `Cmd_build.find_march_files`).
- Records each file's mtime; loops: sleep `interval`, rescan, and if the set changed (file added, removed, or mtime advanced) run the chosen action once, print a one-line status (`✓ built in 1.2s` / `✗ 3 errors`), and keep watching.
- Debounce: coalesce rapid successive changes (e.g. editor save bursts) into one run by re-checking after a short settle delay.
- Ctrl-C exits cleanly. Never exits on a build/test failure — it reports and keeps watching.

**Implementation.**
- New `forge/lib/watcher.ml` with a **pure** core:
  - `type snapshot = (string * float) list` (path → mtime).
  - `snapshot_of : string list -> snapshot` (stats files; the only impure part — keep thin).
  - `changed : prev:snapshot -> cur:snapshot -> bool` — **pure**, the unit-test target: true if any path added/removed or mtime increased.
- New `forge/lib/cmd_watch.ml`: `run ~action ~interval ~clear ()` — builds the file list (via `Cmd_build.find_march_files` + fixed extras), then loops with `Unix.sleepf`, calling `Cmd_build.build` / `Cmd_test.run` / `Cmd_run.run` per `action`. Polling (mtime scan) is chosen over `inotify`/`fsevents` to stay dependency-free and cross-platform.
- Wire `watch_cmd` in `main.ml` (positional `action`, `--interval`, `--clear`).

**Testing plan.**
- *Unit* (new `"watcher"` group in `test_forge.ml`):
  - `changed` returns false for identical snapshots.
  - true when a file's mtime advances.
  - true when a path is added; true when a path is removed.
  - false when order differs but contents identical (normalize/sort).
- *e2e*: scaffold a project, start `forge watch build --interval 100` in the background, `touch lib/app.march`, assert a rebuild line appears within ~1s; modify the file to introduce an error, assert the next run reports the error and the watcher stays alive; kill it. (Scripted with a short interval and a timeout.)

**Documentation.**
- README: new "Development workflow" subsection with `forge watch` examples.
- Command reference / `forge watch --help` doc string covering the three actions and flags.
- `specs/todos.md` → Done; `specs/progress.md` → Current State entry.

---

## 2. `forge bench`

**Motivation.** March already ships `bench/*.march`, a `bench/dune`, `bench/RESULTS.md`, and a `specs/benchmarks.md` mapping features to benchmarks — but there's no first-class way to run them. `CLAUDE.md` even instructs running benchmarks after feature changes. `forge bench` makes that a one-liner and gives regression-tracking output.

**CLI surface.**
```
forge bench                 # compile + run every bench/*.march, --release
forge bench binary_trees    # run one by name
forge bench --filter tree   # substring filter
forge bench --json          # machine-readable timings (for CI tracking)
```

**Behavior.**
- Discovers benchmarks by convention: each `bench/*.march` with a `main()` is a benchmark (named by its filename stem). Optionally honor `[[bench]]` entries in `forge.toml` later; convention first.
- Compiles each with the resolved toolchain at `--opt 2` (release) via the same path as `forge build`, runs the binary, and reports wall-clock time (`Unix.gettimeofday` around the run). Non-zero exit from a benchmark is a failure surfaced in the summary.
- Output: a table `name | time` (human) or JSON array (`--json`) suitable for diffing across runs / storing in CI.

**Implementation.**
- New `forge/lib/cmd_bench.ml`:
  - `discover : root -> (name * path) list` — **pure-ish** (lists `bench/*.march`); the name/path derivation is the unit-test target.
  - `run ~filter ~json ()` — for each discovered bench: compile via `Cmd_build.compile_entry`-style invocation (reusing `Cmd_build.lib_path_env`, which already routes through the resolved toolchain), time the run, collect results.
  - `format_results : (name * float * bool) list -> json:bool -> string` — **pure**, unit-test target.
- Wire `bench_cmd` in `main.ml`.

**Testing plan.**
- *Unit* (new `"bench"` group):
  - `discover` returns `[(stem, path)]` for files in a temp `bench/`, ignores non-`.march`, ignores subdirs without `main` (or documents that detection is filename-based).
  - `format_results` renders the human table and the JSON form deterministically (including a failed bench row).
  - `--filter` selection logic (pure predicate) keeps only matching names.
- *e2e*: a project with a trivial `bench/noop.march` (`fn main() do () end`); `forge bench` compiles+runs+prints a time and exit 0; `forge bench nope` reports "no benchmark matched".
- Wire one bench into the existing CI/`runtest` only as a smoke test (compile+run), not a timing assertion (timings are environment-dependent).

**Documentation.**
- README: "Benchmarking" subsection.
- Cross-link `specs/benchmarks.md` (note `forge bench` as the runner) and update it.
- `forge bench --help`; `specs/todos.md`/`progress.md` updates.

---

## 3. Release ergonomics — `forge version` / `forge release`

**Motivation.** Cutting a release today is manual: edit `forge.toml`, tag git, run checks. Two small commands remove the friction. (Note: `forge format --check` and `forge lint`'s non-zero CI exit **already exist** — `cmd_format.ml` takes `~check`, `cmd_lint.ml` returns `Error "lint found errors"` — so the "CI modes" part of this item is done; this section is the *version/release* part.)

**CLI surface.**
```
forge version                 # print the current version
forge version patch|minor|major
forge version set 1.4.0
forge version <bump> --tag    # also create an annotated git tag vX.Y.Z
forge release                 # orchestrate: checks -> version bump -> tag (-> publish)
```

**Behavior.**
- `forge version <bump>`: parse `proj.version` with `Resolver_version.parse`, apply the bump (patch/minor/major reset lower fields; `set` takes an explicit semver), rewrite the `version = "..."` line in `forge.toml` in place (textual edit, like `Cmd_add` inserts dep lines — preserve comments/formatting), and print old → new.
- `--tag`: after writing, `git tag -a vX.Y.Z -m "vX.Y.Z"`. Refuse if the tag already exists or the tree is dirty (configurable).
- `forge release`: a guarded pipeline — verify clean git tree, `forge build` + `forge test` pass, bump version, create tag, and (once a registry exists) `forge publish`. Each step gated; abort with a clear message on failure. Until the registry lands, `release` stops before publish and prints the manual push step.

**Implementation.**
- Pure core in a new `forge/lib/versioning.ml`:
  - `bump : [patch|minor|major] -> Resolver_version.t -> Resolver_version.t` — **pure**, primary unit-test target.
  - `rewrite_version_line : toml:string -> new_version:string -> string` — **pure** textual rewrite of the `[package]` `version` key, unit-test target (must touch only `[package].version`, not a dep's `version`).
- New `forge/lib/cmd_version.ml` and `forge/lib/cmd_release.ml` orchestrating reads/writes + `git` via `Sys.command`.
- Wire `version_cmd`, `release_cmd` in `main.ml`.

**Testing plan.**
- *Unit* (new `"versioning"` group):
  - `bump`: `patch 1.2.3 → 1.2.4`; `minor 1.2.3 → 1.3.0`; `major 1.2.3 → 2.0.0`; bump clears pre-release.
  - `rewrite_version_line`: bumps `[package].version` only; leaves a `[deps] foo = { version = "1.0.0" }` line untouched; preserves surrounding lines/comments; idempotent for `set` to the same value.
- *e2e*: scaffold; `forge version patch` rewrites `forge.toml` (re-read asserts new version); `forge version 1.0.0 --tag` in a git repo creates `v1.0.0` (assert `git tag` lists it); `forge version major --tag` on a dirty tree errors.
- `forge release` e2e: passing project → runs through; failing test → aborts before tagging.

**Documentation.**
- README: "Releasing a package" section (version bump, tag, the `release` pipeline, and the CI `forge format --check` / `forge lint` checks that already exist).
- `forge version`/`forge release --help`; `specs/todos.md`/`progress.md`.

---

## 4. `forge licenses` + `--frozen`

**Motivation.** Two cheap CI/compliance wins that build directly on work already done. We now parse the `license` field (this session) and have lockfile drift detection (`Resolver_lockfile.has_drifted` + the toolchain drift); `forge licenses` surfaces the former across the dep tree, and `--frozen` promotes drift from a warning to a hard error for reproducible CI.

**CLI surface.**
```
forge licenses              # table of every dependency + its declared license
forge licenses --json
forge build --frozen        # error (don't re-resolve) if forge.lock is missing or drifted
forge deps --frozen
```

**Behavior.**
- `forge licenses`: enumerate dependencies (reuse `Cmd_tree.build_adjacency` or the `forge.lock` entries), locate each dep's directory (`.march/cas/deps/<name>` or its path), read its `forge.toml` `license`, and print `name | version | license`, flagging any `MISSING`. `--json` for tooling. Exit non-zero if `--strict` and any license is missing (CI gate).
- `--frozen` (a.k.a. `--locked`): a flag on `forge build`/`forge deps` that makes lockfile drift fatal — if `forge.toml` changed since `forge.lock` was generated (`has_drifted`) or the lock is absent, **error** instead of silently re-resolving. The toolchain drift (Option B) likewise becomes an error under `--frozen`. This is the CI reproducibility guarantee.

**Implementation.**
- New `forge/lib/cmd_licenses.ml`:
  - `collect : root -> (name * version option * license option) list` — enumerate + read each dep's license (IO).
  - `format : ... -> json:bool -> string` and `any_missing : ... -> bool` — **pure**, unit-test targets.
- `--frozen`: thread a `~frozen` flag through `Cmd_build.build` / `Cmd_deps.run`; where drift is currently a warning/re-resolve, branch to `Error` when `frozen`. Reuse `Resolver_lockfile.has_drifted` and `Toolchain.toolchain_drift`.
- Wire `licenses_cmd` and the `--frozen` flags in `main.ml`.

**Testing plan.**
- *Unit* (new `"licenses"` group):
  - `format` renders the table + JSON deterministically, including a `MISSING` row.
  - `any_missing` true iff some dep has `None` license.
  - frozen-drift decision (extract a pure `frozen_error : drifted:bool -> frozen:bool -> bool`): error only when `drifted && frozen`.
- *e2e*: a workspace of path deps with mixed `license` fields → `forge licenses` lists them, `--strict` exits non-zero when one is missing. `forge build --frozen` on a project whose `forge.toml` was edited after `forge deps` → errors; on an in-sync project → builds.

**Documentation.**
- README: "CI and reproducibility" (`--frozen`) and "License compliance" (`forge licenses`).
- `--help` text; `specs/todos.md`/`progress.md`.

---

## 5. Shell completions + external subcommands

**Motivation.** Completions are table-stakes DX; external subcommands (`forge-x` on PATH → `forge x`, the git/cargo pattern) let the ecosystem extend forge without touching core — the cheapest possible extensibility.

**CLI surface.**
```
forge completions bash|zsh|fish    # print a completion script to stdout
forge mytool ...                   # if not built-in, exec `forge-mytool` from PATH
```

**Behavior.**
- `forge completions <shell>`: emit a static completion script for the shell that completes the known subcommand names and common flags. Users add `eval "$(forge completions zsh)"` to their rc file.
- External subcommands: when `argv[1]` is not a built-in command (and not a help/archive form), look for an executable `forge-<argv[1]>` on `PATH`; if found, `Unix.execvp` it with the remaining args. If not found, fall through to the existing cmdliner "unknown command" error.

**Implementation.**
- Completions: a new `forge/lib/completions.ml` with `script : shell:[bash|zsh|fish] -> subcommands:string list -> string` — **pure**, generates the script text from the subcommand list (kept in sync with the `cmds` list). Wire `completions_cmd`.
- External subcommands: extend the **pre-dispatch** block already in `forge/bin/main.ml` (the one that intercepts `argv` before cmdliner for archive tasks). Add a pure helper `external_subcommand : known:string list -> argv1:string -> path_lookup:(string -> string option) -> string option` returning the resolved `forge-<x>` path, then `Unix.execvp` it. Pure resolution (given a fake PATH lookup) is the unit-test target; the exec is e2e.

**Testing plan.**
- *Unit* (new `"cli-ext"` group):
  - `Completions.script` for each shell contains every subcommand name and is non-empty (snapshot-style assertions on key substrings).
  - `external_subcommand`: returns `Some` for an unknown command when `forge-<x>` is on the (fake) PATH; `None` when it's a known built-in (built-ins win); `None` when no matching executable exists.
- *e2e*: put a `forge-hello` script on `PATH` that echoes a marker; `forge hello a b` runs it with args `a b`; `forge build` is unaffected (built-in still wins). `forge completions zsh` prints a script mentioning `toolchain`, `build`, `watch`, etc.

**Documentation.**
- README: "Shell completions" (per-shell install snippet) and "Extending forge with plugins" (`forge-<name>` convention).
- `--help`; `specs/todos.md`/`progress.md`.

---

## 6. Workspaces

**Motivation.** The one big *structural* feature, and the one most painful to retrofit later — it touches project discovery, resolution, the lockfile, and every command. A monorepo of related March packages (e.g. an app + its libraries) should build/test/lint as a unit with one shared lockfile. Worth designing early even if built last.

**CLI surface.**
```
# root forge.toml:
[workspace]
members = ["app", "lib/core", "lib/web"]

forge build              # at the workspace root: build all members (dep order)
forge build -p core      # build a single member
forge test               # test all members
forge test -p core
```

**Behavior.**
- A root `forge.toml` with a `[workspace]` table and `members` (paths; later globs) defines a workspace. Members are ordinary packages with their own `forge.toml`.
- `Project.load` learns to detect context: walking up, a `[workspace]` root makes the cwd part of a workspace. A command run at the root applies to all members (in inter-member dependency order); `-p <name>` selects one; a command run inside a member applies to that member.
- **One `forge.lock` at the workspace root** covering all members' dependencies (unified resolution), so members share consistent versions.
- Inter-member path deps resolve within the workspace.

**Phasing (this is multi-PR):**
- **Phase 1** — parse `[workspace].members`; `forge build`/`test`/`lint` iterate members; `-p` selector; workspace-root detection in `Project`. (No unified lock yet — each member keeps its own.)
- **Phase 2** — single workspace-root `forge.lock`; unified resolution across members.
- **Phase 3** — inter-member dependency ordering (topological) and "affected-only" runs (`forge test --changed`).

**Implementation.**
- `forge/lib/workspace.ml` (pure where possible):
  - `parse_members : Toml.document -> string list` — **pure**, unit-test target.
  - `find_root : start_dir -> string option` — walk up for a `[workspace]` `forge.toml` (mirrors `Toolchain.find_pin`'s walk).
  - `member_order : members:(name * deps) list -> name list` — **pure** topological sort (Phase 3), unit-test target (incl. cycle detection).
- `Project`: add workspace awareness (is-member, workspace-root path, member list).
- `Cmd_build`/`Cmd_test`/`Cmd_lint`: when at a workspace root with no `-p`, iterate members and aggregate results (fail if any member fails); honor `-p`.
- Wire a `-p`/`--package` flag on the relevant commands in `main.ml`.

**Testing plan.**
- *Unit* (new `"workspace"` group):
  - `parse_members` extracts the list from a `[workspace]` table; empty/absent → `[]`.
  - `find_root` locates the workspace root from a nested member dir; `None` when none exists.
  - `member_order` (Phase 3): topological order for `app → core`, `web → core`; detects a cycle and errors.
- *e2e*: a workspace with two members (`app` depending on `core` via a path dep) → `forge build` at the root builds both (assert both binaries/outputs); `forge build -p core` builds only `core`; a compile error in `core` fails the whole-workspace build with a clear "member core failed" message.

**Documentation.**
- New `docs/workspaces.md` page (the structural concepts, the `[workspace]` schema, member layout, `-p` selector, shared lock).
- README: "Workspaces" subsection linking to the page.
- `specs/todos.md`/`progress.md`; update `forge.toml` schema docs.

---

## Suggested order

1. **`forge watch`** — highest daily value, self-contained, no schema/lock changes.
2. **`forge bench`** — leverages existing `bench/` assets; small.
3. **`forge licenses` + `--frozen`** — cheap, builds on this session's metadata + drift work; immediate CI value.
4. **`forge version` / `forge release`** — small, removes release friction.
5. **Shell completions + external subcommands** — cheap extensibility; the plugin hook future-proofs the CLI.
6. **Workspaces** — last and phased; the only one that changes core data model, so do it deliberately once the rest is stable.

Items 1–5 are each ~a session of work (pure core + thin IO + tests + docs). Item 6 is three phases.

## Out of scope (needs a registry server — see forge_version_manager.md)

`forge publish` network push, `forge outdated`, `forge audit` (advisory DB), `forge yank`, registry auth/mirrors, SBOM/signing. These are tracked separately and gated on building the registry, which is a large effort of its own.
