---
name: forge-add
description: Add a dependency to a March project's forge.toml (registry, git, or local path), including dev- and test-only dependencies and the capability-baseline check. Use when a project needs a new library.
---

# forge add

`forge add NAME` writes a new dependency line into `forge.toml`. There are four sources: registry (default), git, git at a ref, and local path.

## Forms

### Registry (default)

```bash
forge add conduit
forge add bastion
```

Uses the forge archive registry. Choose the table with a flag:

```bash
forge add --dev some_helper        # [dev-deps]: dev and test
forge add --test some_test_helper  # [test-deps]: tests only
forge add --dev-only some_tool     # [dev-only-deps]: dev only, not tests
```

### Capability baseline

If the project has a capability baseline (`forge.caps.lock`, written by `forge audit --record`),
every dependency the add brings in or changes is compared against it. One that asks for a
capability the baseline does not grant is refused: the delta is printed, `forge.toml` and
`forge.lock` are restored, and the command exits non-zero. Read the delta, then re-run with
`--accept-caps` only if the new capabilities are intended (it records them in the baseline).

### Git

```bash
forge add my_lib --git=https://github.com/user/my_lib.git
forge add my_lib --git=https://github.com/user/my_lib.git --branch=develop
forge add my_lib --git=https://github.com/user/my_lib.git --tag=v1.2.0
forge add my_lib --git=https://github.com/user/my_lib.git --rev=abc123
```

`--rev` pins an exact commit; `--tag` pins a named tag; `--branch` tracks a branch (default `main`).

### Local path

```bash
forge add my_lib --path=/Users/me/code/my_lib
```

Use for local development when iterating on a library and its consumer together.

### Overwrite existing

```bash
forge add my_lib --force
```

Required if `my_lib` is already in `forge.toml`.

## After adding

1. `forge add` resolves the dependency itself. `forge deps` installs everything `forge.lock`
   names (after a manual `forge.toml` edit); `forge deps update [NAME]` updates.
2. Run `forge search --rebuild` so subsequent searches include the new module.
3. Import it in a `.march` file: `use MyLib` (or whatever the module name is).
4. Run `forge check` to confirm the types line up.

## Verifying what was added

Check `forge.toml`: the new entry appears under `[deps]` (or `[dev-deps]`, `[test-deps]`,
`[dev-only-deps]`), and `forge.lock` records the resolved version.

If you're unsure of the correct module name for a registry dep, `forge archives` lists the
installed archives, and `forge search` after install surfaces its public modules.
