# forge puts dep `test/`/`priv/` dirs and UNLOCKED dep versions on MARCH_LIB_PATH

Logged 2026-10-02 while verifying forgepm's pooled Repo (sub-project A).

`forge build` on an untouched forgepm `origin/main` (e90b7e8) checkout fails
with 193 typecheck errors, none in forgepm files: 226 diagnostics come from
`~/.march/cas/deps/depot/<locked>/test/*.march` and ~2156 each from the
`priv/migrations/` dirs of THREE cached conduit versions (`300df50` = locked,
`3eefefd`, `825180d`). `forge/lib/cmd_build.ml` `lib_path_env` →
`dep_to_lib_paths` expands a dep into "root plus all descendant directories",
which sweeps in `test/` and `priv/`, and the cached-version walk is not
restricted to the `forge.lock` coordinate. A curated path (each locked dep's
`lib/` only) typechecks the same tree with 0 forgepm errors.

Fix: expand only `<dep>/lib/**` (plus whatever the dep's own forge.toml
declares as source), and select exactly the locked version per dep. Add a
forge test with a dep that ships a deliberately broken `test/` file.

## Fixed 2026-10-06: the offender was the LSP's own resolver

On current main, `forge build`'s path is already right. A probe printing
`Cmd_build.lib_path_env` for that forgepm checkout gives exactly one directory
tree per dep: the forge.lock coordinate's `lib/` and its subdirectories
(`conduit/825180d…/lib/**`, `depot/888fcf7…/lib/**`, `bastion/0.3.1/lib/**`,
`march_doc/1cf6085…/lib/**`). There is no `test/`, no `priv/`, and no unlocked
version. The version-aware cache layout (2026-09-12) and `Project.dep_coords`
handle that.

The reported set (a dep's `test/`, the `priv/migrations` of several cached
conduit versions) is what `lsp/lib/forge_config.ml` produced. That was a
second, hand-written resolver, kept "self-contained" although the LSP library
already linked `march_forge`. It ignored forge.lock and resolved a git dep to
`~/.march/cas/deps/<name>`. Under the version-keyed layout that directory is
the container of every cached version and has no `lib/`, so the
"else the root itself" fallback put the whole container, recursively, on the
search path: every version's `lib/`, `test/`, `priv/` and `specs/`. It also
skipped registry deps (`bastion = "0.3.1"`) and transitive deps entirely.
Every editor diagnostic, and anything else routed through
`Analysis.analyse`, typechecked against that tree.

Fix: `Forge_config.project_lib_paths` now returns
`March_forge.Cmd_build.lib_paths` (new: the list `lib_path_env` quotes into
`MARCH_LIB_PATH=`). The LSP sees exactly what `forge build` compiles against,
including registry and transitive deps. A forge.toml that does not load
mid-edit falls back to the project's own directories. The duplicate TOML
parser and resolver are deleted.

Regression: `lsp/test` `cross-file` / "dep lib paths follow forge.lock". A
fake HOME holds a git dep at two cached coordinates, each with a valid `lib/`
and ill-typed `test/` and `priv/` files, and forge.lock names one coordinate.
The test asserts the dep paths are exactly `<locked>/lib`, and that a project
file calling the dep typechecks clean. With the old resolver it fails: the
received path is the bare container `~/.march/cas/deps/widget`.
