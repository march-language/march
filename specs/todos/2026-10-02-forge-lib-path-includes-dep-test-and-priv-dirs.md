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
