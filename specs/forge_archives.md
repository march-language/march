# Forge Archives

Forge archives are globally-installed packages of forge task definitions. They let library authors ship CLI commands (like `forge bastion.new` or `forge depot.gen.migration`) that work outside of any specific project — solving the chicken-and-egg problem where scaffolding tools need to run before the project they're scaffolding exists.

## Motivation

March libraries like Bastion and Depot ship forge tasks: subcommands that appear on the `forge` CLI when the library is a project dependency. `forge depot.gen.migration add_users` generates a migration file; `forge bastion.gen.auth` scaffolds authentication boilerplate. These work today because forge discovers task modules in `deps/<name>/forge/` and runs them in-project context.

The problem: `forge bastion.new my_blog` needs to run *before* a project exists. There is no `forge.toml`, no `deps/` directory, no project root. The task that creates the project cannot itself be a project dependency.

Elixir solved this exact problem with `mix archive.install`. Forge archives are the same mechanism: a named, versioned, globally-installed package containing only forge task definitions. Archives live in `~/.march/archives/`, are fetched from the registry, a git repo, or a local path, and are available on the `forge` CLI in any directory — including outside any project.

### What archives are NOT

- Archives are not libraries. You cannot `import Bastion` from an archive. The installed archive is task code only, not the full library.
- Archives are not build tools. They do not replace `forge build` or participate in compilation.
- Archives are not isolated environments. All archives share the same March runtime.

## CLI Commands

### `forge install`

Install an archive globally. The argument is `<name>[@<ref>]` where `<ref>` determines the source:

| Form | Meaning |
|------|---------|
| `forge install bastion` | Latest version from registry |
| `forge install bastion@1.1.0` | Exact version from registry |
| `forge install bastion@latest` | Explicit latest (same as no ref) |
| `forge install bastion@../bastion` | Local path (ref starts with `.` or `/`) |
| `forge install bastion@https://github.com/march-lang/bastion` | Git, default branch |
| `forge install bastion@https://github.com/march-lang/bastion#v1.2.0` | Git, specific tag or branch |

Examples:

```
$ forge install bastion
Resolving bastion...
Fetching bastion 1.2.0 from registry...
Verifying checksum... ok
Installing bastion 1.2.0 to ~/.march/archives/
Done. Tasks available: bastion.new, bastion.gen.auth, bastion.server

$ forge install bastion@1.1.0
$ forge install bastion@../bastion
$ forge install bastion@https://github.com/march-lang/bastion#main
```

Forge infers the source from the ref:
- Semver string or `latest` → registry
- Starts with `/`, `./`, `../` → local filesystem path (re-read on every invocation, not CAS-backed)
- Starts with `https://`, `http://`, or `git@` → git clone; an optional `#tag-or-branch` fragment pins the ref

For git installs without a `#` fragment, the default branch is used. Git archives are registered under the package name declared in the fetched archive's `forge.toml`.

**Flags:**

| Flag | Description |
|------|-------------|
| `--force` | Reinstall even if the version is already installed |
| `--no-verify` | Skip checksum verification (not recommended) |

### `forge uninstall`

Remove a globally installed archive.

```
$ forge uninstall bastion
Uninstalled bastion 1.2.0.
```

Prints an error if the archive is not installed. Does not remove CAS blobs that may be shared with other archives; those are collected by `forge cache clean`.

### `forge archives`

Show all installed archives.

```
$ forge archives
bastion  1.2.0  registry  tasks: bastion.new, bastion.gen.auth, bastion.server
depot    0.9.1  registry  tasks: depot.gen.migration, depot.gen.schema
conduit  0.3.0  git       https://github.com/march-lang/conduit (main@abc1234)
(dev)    --     path      /Users/chase/src/mylib/
```

The `(dev)` entry for local-path archives shows the resolved path.

### `forge update`

Update one or all archives to their latest compatible versions.

```
$ forge update          # update all
$ forge update bastion  # update one
```

For registry archives, "latest compatible" means the newest version satisfying the original constraint (or `*` if installed without a version pin). Git branch archives fetch the latest commit on the tracked branch. Git tag and rev archives are pinned and cannot be updated (forge prints a notice).

```
$ forge update bastion
bastion: 1.2.0 → 1.3.1
Fetching bastion 1.3.1 from registry...
Verifying checksum... ok
Done. Previous version (1.2.0) retained in CAS.
```

## Storage

Archives are stored at `~/.march/archives/`. This directory is created on first install.

```
~/.march/
├── archives/
│   ├── registry.toml          # installed archive manifest (name → version + hash)
│   ├── bastion/               # symlink tree into CAS
│   │   ├── forge.toml         # the archive's forge.toml (metadata + task declarations)
│   │   └── forge/             # task modules
│   │       ├── tasks.march    # task entry points (or multiple files)
│   │       └── ...
│   ├── depot/
│   │   ├── forge.toml
│   │   └── forge/
│   │       └── tasks.march
│   └── dev/                   # local-path dev archives (not CAS-backed)
│       └── mylib -> /Users/chase/src/mylib/
└── cas/
    └── packages/
        └── <sha256>/          # existing package CAS (archives reuse this)
            ├── archive
            └── info.toml
```

### `registry.toml`

The global installed-archive manifest. Tracks what is installed, where it came from, and what content hash is expected.

```toml
[bastion]
version = "1.2.0"
source  = "registry"
hash    = "sha256:abc123..."
installed_at = "2026-04-01T10:00:00Z"

[depot]
version = "0.9.1"
source  = "registry"
hash    = "sha256:def456..."
installed_at = "2026-03-28T08:00:00Z"

[conduit]
version = "0.3.0"
source  = "git"
url     = "https://github.com/march-lang/conduit"
branch  = "main"
rev     = "abc1234"
hash    = "sha256:789abc..."
installed_at = "2026-03-15T14:00:00Z"
```

Path archives are not recorded in `registry.toml`; they are tracked in a separate `dev.toml` that maps names to absolute paths.

### CAS integration

Archive source trees are stored in the existing package CAS at `~/.march/cas/packages/<sha256>/`, using the same canonical archive format as regular dependencies (see `resolver_cas_package.ml`). The `~/.march/archives/<name>/` directory is a symlink tree pointing into the CAS, identical in structure to how project `deps/` directories work.

This means:
- Two libraries with a shared archive version share disk bytes.
- Updating an archive installs the new version into CAS before changing the symlink; the old version remains accessible until `forge cache clean`.
- Integrity verification re-hashes the CAS entry on demand (`forge verify`).

Local-path archives bypass the CAS entirely: forge reads them directly from the filesystem on each invocation.

## Task Discovery and Resolution

### Discovery order

When forge encounters an unknown subcommand (e.g. `forge bastion.new`), it resolves which task module to run in this order:

1. **Project-local deps.** If a `forge.toml` is found in the current directory or any parent, forge checks `deps/<name>/forge/` for task modules matching the namespace prefix. Project-local tasks shadow global archives with the same name.
2. **Global archives.** Forge checks `~/.march/archives/<name>/forge/` for task modules matching the prefix.
3. **Dev archives.** Forge checks path-tracked dev archives.
4. **Not found.** Forge prints:
   ```
   error: unknown command 'bastion.new'
   hint: install the bastion archive with: forge install bastion
   ```

The project-local shadow rule is the same as Mix: if your project depends on `bastion` at a version that differs from your globally installed archive, the project wins. This ensures consistent behavior within a project regardless of what's globally installed.

### Namespace conventions

Tasks are namespaced by archive name. The namespace is the first dotted segment of the command:

| Command | Archive | Task entry |
|---------|---------|-----------|
| `forge bastion.new` | `bastion` | `new` |
| `forge bastion.gen.auth` | `bastion` | `gen.auth` (nested namespace) |
| `forge depot.gen.migration` | `depot` | `gen.migration` |

The archive name must match the package name in `forge.toml`. Forge does not allow archive names that conflict with built-in forge commands (`build`, `run`, `test`, `deps`, `install`, `uninstall`, `archives`, `update`, `verify`, `publish`, `search`, etc.).

### Version resolution

Only one version of a given archive can be installed globally at a time. If you need a specific version in a project, add the library as a regular `[deps]` entry in `forge.toml`; the project-local version shadows the global archive automatically.

`forge install bastion@1.1.0` when `bastion 1.2.0` is already installed asks for confirmation:

```
bastion 1.2.0 is already installed. Replace with 1.1.0? [y/N]
```

If confirmed, the previous version is removed from `registry.toml` (but its CAS entry is retained until `forge cache clean`).

### Task invocation

Forge invokes archive tasks by:

1. Locating the resolved archive directory (local dep or global archive).
2. Loading the task module declared for the matched command.
3. Calling the task's `main(args: List(String))` function, passing any remaining CLI arguments.
4. The task module has access to the full March stdlib and any deps declared in the archive's `[archive-deps]` section (see Archive Format below).

Tasks run in the user's current working directory, not the archive directory. A scaffolding task like `bastion.new` receives the CWD as its working directory and creates the new project there.

## Archive Format

### What makes a library an archive

A March library becomes an archive-capable package by adding an `[archive]` section to its `forge.toml` and placing task modules in a `forge/` directory at the package root.

Minimal example — `bastion/forge.toml`:

```toml
[project]
name    = "bastion"
version = "1.2.0"
type    = "lib"
description = "Full-stack web framework for March"

[archive]
tasks = [
  { command = "bastion.new",      module = "forge/cmd_new.march" },
  { command = "bastion.gen.auth", module = "forge/cmd_gen_auth.march" },
  { command = "bastion.server",   module = "forge/cmd_server.march" },
]

# Deps that archive tasks need at runtime (NOT the full library deps)
[archive-deps]
toml   = { registry = "forge", version = "~> 1.0" }
clap   = { registry = "forge", version = "~> 0.4" }
```

### The `[archive]` section

| Field | Type | Description |
|-------|------|-------------|
| `tasks` | array of task entries | Maps command names to module files |
| (future) `description` | string | Short description shown in `forge archives` |

Each task entry:

| Field | Type | Description |
|-------|------|-------------|
| `command` | string | The forge subcommand (must start with archive name prefix) |
| `module` | string | Path to the `.march` file, relative to the package root |

### The `[archive-deps]` section

Archive tasks often need lightweight helper libraries (argument parsing, TOML, color output) but do NOT need the full library they belong to. The `[archive-deps]` section declares only what the forge tasks themselves require at runtime.

These deps are resolved and fetched when the archive is installed, stored alongside the archive in `~/.march/archives/<name>/deps/`, and made available to task modules at invocation time.

`[archive-deps]` accepts the same dep forms as `[deps]`: registry, git, and path.

### Task module interface

Each task module must export a `main` function:

```march
fn main(args: List(String)) -> Int
```

The return value is the process exit code. Conventionally, `0` means success and non-zero is an error.

Task modules may import from:
- The March stdlib (always available)
- Packages declared in `[archive-deps]`
- Other modules within the same `forge/` directory (relative imports)

Task modules may NOT import from the library's own `lib/` directory. This keeps archive tasks self-contained and prevents the archive from needing to compile the full library on install.

### Files included in an archive

When `forge publish` packages a library, or when `forge install bastion@../path` or `forge install bastion@https://...` installs from source, the archive extraction includes:

- `forge.toml` (required)
- The entire `forge/` directory (required — this is the task code)
- `forge.lock` for the archive-deps resolution (if present; generated during install if absent)

The following are explicitly excluded from archive extraction (they are part of the library, not the tasks):

- `lib/` — library source (not needed by tasks)
- `test/` — test code
- `bench/` — benchmarks
- `deps/` — project dependencies (tasks get their own `archive-deps`)
- `.march/` — build artifacts

The extracted archive is thus much smaller than the full library source tree. A well-structured archive should be a few KB of task code plus a lockfile.

### Publishing archives to the registry

An archive is published the same way a library is: `forge publish`. The registry stores it as a normal package. The presence of an `[archive]` section in `forge.toml` is what tells forge (and the registry) that this package can also be installed as an archive.

Libraries may be both a dependency AND an archive. `bastion` is a library (added to `[deps]`) AND an archive (installed with `forge install bastion`). When used as a dep, the full `lib/` is available for import. When installed as an archive, only the `forge/` tasks are extracted and invoked.

## Security

### Checksum verification

Every archive installation from the registry or a git tag verifies a SHA-256 checksum before unpacking. The workflow:

1. Fetch the archive (canonical archive bytes, same format as the package CAS).
2. Compute `sha256` of the fetched bytes.
3. For registry installs: compare against the checksum published by the registry alongside the package metadata.
4. For git tag installs: the checksum is computed locally and stored in `registry.toml`; future integrity checks re-verify against this stored hash.
5. For git branch installs: the checksum is stored per-commit and changes on update (expected). `forge archives` shows the tracked ref and hash.
6. If the computed hash does not match, abort with:
   ```
   error: checksum mismatch for bastion 1.2.0
     expected: sha256:abc123...
     got:      sha256:def456...
   Refusing to install. The download may be corrupt or tampered.
   Run 'forge install bastion@1.2.0 --force' to re-fetch.
   ```

Local-path archives (`--path`) are not checksummed — they are assumed to be trusted developer-local source trees.

### Integrity verification

`forge verify [name]` re-hashes installed archives and checks them against `registry.toml`:

```
$ forge verify
bastion  1.2.0  ok
depot    0.9.1  ok
conduit  0.3.0  ok
```

On mismatch, forge reports the corrupt archive and suggests reinstallation. This command is also run automatically by `forge install` and `forge update`.

### Trust model

The archive trust model is the same as the package registry trust model:

- **Registry packages** are implicitly trusted if their checksum matches the registry-published hash. The registry is the trust root.
- **Git archives** are trusted if the fetched content matches the stored hash for a tag, or if the developer explicitly accepted the updated hash on `forge update` for a branch.
- **Path archives** are fully trusted — the developer controls the local filesystem.

There is no code signing in the initial implementation. If the March package registry later adds publisher key signing (analogous to Hex's package signing), archive verification will use the same mechanism.

### Privilege isolation

Archive tasks run as the invoking user with no special privileges. They cannot escalate permissions, access network resources without the user's stdlib APIs, or modify the forge installation directory (except through `forge install` / `forge uninstall` themselves). Tasks are March programs subject to the same type system and runtime constraints as any other March code.

## Migration Path

### Bastion

Bastion's forge tasks (`bastion.new`, `bastion.gen.auth`, `bastion.server`) are currently implemented in March code inside the Bastion repo and loaded when Bastion is a project dep. Migration steps:

1. Move task modules from their current location to `bastion/forge/`:
   - `forge/cmd_new.march`
   - `forge/cmd_gen_auth.march`
   - `forge/cmd_server.march`
2. Add `[archive]` section to `bastion/forge.toml` mapping each command to its module.
3. Identify task-only deps (argument parsing, file I/O helpers) and move them to `[archive-deps]`. Remove unused deps from the archive scope.
4. Test with `forge install bastion@../bastion` locally.
5. Publish via `forge publish`. Users then run `forge install bastion` once and get `forge bastion.new` globally.

After migration, Bastion as a project dependency continues to provide `forge bastion.*` tasks for within-project commands (e.g. `forge bastion.gen.auth` inside an existing Bastion app). The global archive provides the same tasks outside projects.

### Depot

Depot's tasks (`depot.gen.migration`, `depot.gen.schema`) operate on existing project files and typically require a database connection configured in the project. These make less sense as bootstrap tasks, but the same migration applies:

1. Move task modules to `depot/forge/`.
2. Add `[archive]` section.
3. `[archive-deps]` will likely include a TOML parser and Depot's own config reader, but NOT the full Depot library (tasks read config files, they don't compile Depot).
4. Note: `depot.gen.migration` may warn when run outside a Depot project rather than failing hard — the archive provides the command globally but it self-validates its context.

### Conduit

Conduit follows the same pattern as Depot. Any library that ships forge tasks can be migrated by adding the `[archive]` section and `forge/` directory. The migration is purely additive: existing project-dep behavior is unchanged.

### Rollout timeline

The `[archive]` section in `forge.toml` is ignored by older versions of forge (unknown TOML sections are tolerated). Libraries can add archive support without breaking users on older forge versions. The `forge install`, `forge uninstall`, `forge archives`, and `forge update` commands are simply absent on older forge; users who want archive installation upgrade forge first.

## Future Work

These are out of scope for the initial implementation:

- **Task composability.** Allow archive tasks to invoke other archive tasks or forge built-ins programmatically.
- **Archive namespacing conflicts.** If two archives claim the same command prefix, forge currently installs the newer one. A warning and conflict resolution UI could be added.
- **Archive lockfile.** A global `~/.march/archives/registry.lock` with exact resolved hashes for `archive-deps`, analogous to `forge.lock`. Currently `archive-deps` are re-resolved on install.
- **Windows support.** Path handling, symlink alternatives, and installer changes needed.
- **`forge new --archive`** flag on `forge new` to scaffold a library with the `forge/` directory structure and `[archive]` section boilerplate pre-populated.
