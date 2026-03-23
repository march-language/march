# Forge — The March Build Tool & Package Manager

**Status:** Design Spec (v0.1)
**Date:** March 23, 2026

---

## 1. Philosophy

Forge is the single entry point for the March developer experience. It scaffolds projects, compiles code, manages dependencies, runs tests, formats source, and launches the REPL. It is to March what Cargo is to Rust and Mix is to Elixir — a unified, opinionated tool that drives the entire development lifecycle.

Forge drives the March compiler directly. There is no dune, no opam, no Makefile in the picture. Forge is a standalone build system that integrates with March's existing Content-Addressed Store (CAS) for reproducible, cached builds.

---

## 2. Commands

| Command | Alias | Description |
|---|---|---|
| `forge new <name> [--app\|--lib\|--tool]` | | Scaffold a new project (default: `--app`) |
| `forge build [--release]` | | Compile the project |
| `forge run` | | Build and execute (for `app` and `tool` projects) |
| `forge test` | | Discover and run test files in `test/` |
| `forge format` | | Format source code (delegates to existing `march fmt`) |
| `forge interactive` | `forge i` | Launch the March REPL with the project loaded |
| `forge deps` | | Fetch and manage dependencies |
| `forge clean [--cas\|--all]` | | Remove build artifacts (with `--cas` or `--all` for deeper clean) |

### 2.1 `forge new`

Creates a new project directory with the specified template, initializes a git repository (`git init`), and generates all scaffolding files.

```
forge new my_project            # creates an app (default)
forge new my_project --app      # supervised application (explicit)
forge new my_project --lib      # library
forge new my_project --tool     # executable that runs and terminates
```

### 2.2 `forge build`

Compiles the project by driving the March compiler directly. Integrates with the CAS for incremental, content-addressed builds. Outputs go to `.march/build/`.

- Default mode: debug (fast compilation, better error messages).
- `--release`: optimized build (included from day one, may be a no-op until the compiler has distinct optimization passes).

### 2.3 `forge run`

Builds the project (if needed) and executes it. Available for `app` and `tool` project types. Not available for `lib` projects (no entrypoint).

### 2.4 `forge test`

Discovers and runs all test files in the `test/` directory. The test framework and syntax are a separate design effort — forge's responsibility is discovery and execution.

### 2.5 `forge format`

Delegates to the existing `march fmt` implementation (`lib/format/format.ml`). Supports `--check` mode for CI. Style rules are owned by the existing formatter: 2-space indent, `do...end` blocks, `|`-aligned match arms, `|>` at start of continuation lines, trailing whitespace removal, single trailing newline.

### 2.6 `forge interactive` / `forge i`

Launches the March REPL with the current project's modules and dependencies loaded.

### 2.7 `forge deps`

Fetches and manages project dependencies as declared in `forge.toml`. Writes resolved versions to `forge.lock`.

- `forge deps` — fetch all deps
- `forge deps update <name>` — update a specific dependency

### 2.8 `forge clean`

Three levels of cleanup:

- **`forge clean`** — removes compiled artifacts from `.march/build/` only (safe, fast, no cache loss)
- **`forge clean --cas`** — also prunes the local CAS (`.march/cas/`), reclaims space but next build re-hashes
- **`forge clean --all`** — nukes the entire `.march/` directory (build + CAS, full reset)

---

## 3. Project Templates

### 3.1 `--app` (default) — Supervised Application

A long-running application with an actor system and supervision trees. This is the default because March is designed for building real systems.

```
my_project/
├── lib/
│   └── my_project.march       # minimal supervised main
├── test/
│   └── my_project_test.march
├── forge.toml
├── .editorconfig
├── .gitignore
└── README.md
```

The generated `lib/my_project.march` contains a minimal supervised application entrypoint — just enough to demonstrate the pattern, not a tutorial.

### 3.2 `--lib` — Library

A library meant to be imported by other March projects. No entrypoint, no `forge run`.

```
my_project/
├── lib/
│   └── my_project.march       # module with public API
├── test/
│   └── my_project_test.march
├── forge.toml
├── .editorconfig
├── .gitignore
└── README.md
```

### 3.3 `--tool` — Executable

A project with a `main` that runs and terminates. Can have dependencies, complex structure, and multiple modules — but it's not a long-running service.

```
my_project/
├── lib/
│   └── my_project.march       # main entrypoint
├── test/
│   └── my_project_test.march
├── forge.toml
├── .editorconfig
├── .gitignore
└── README.md
```

### 3.4 Common to All Templates

All templates generate:

- **`forge.toml`** — project configuration (see section 4)
- **`.editorconfig`** — editor-neutral formatting config (see section 8)
- **`.gitignore`** — contains `/.march/`
- **`README.md`** — minimal readme with project name
- **`git init`** — repository is initialized automatically

The `.march/` directory is created on first build, not at scaffold time:

```
.march/                        # gitignored, managed by toolchain
├── cas/                       # content-addressed store (existing)
└── build/                     # compiled artifacts
```

---

## 4. Project Configuration — `forge.toml`

```toml
[project]
name = "my_project"
version = "0.1.0"
description = ""
type = "app"                   # app | lib | tool
march = "0.1.0"               # minimum March compiler version

[deps]
http = { git = "https://github.com/user/march-http.git" }
json = { path = "../march-json" }

[dev-deps]

[profile.release]
opt_level = 3
strip = true
```

### 4.1 `[project]`

- **`name`** — project name (derived from the directory name at scaffold time)
- **`version`** — semver version string
- **`description`** — optional one-line description
- **`type`** — project template type: `app`, `lib`, or `tool`
- **`march`** — minimum required March compiler version

### 4.2 `[deps]` and `[dev-deps]`

Dependencies are specified as git URLs or local paths:

```toml
[deps]
http = { git = "https://github.com/user/march-http.git" }
json = { path = "../march-json" }
utils = { git = "https://github.com/user/march-utils.git", rev = "main" }
```

`[dev-deps]` follows the same format and is only used for test and development builds.

### 4.3 `[profile.release]`

Compiler flags for release builds. Applied when `forge build --release` is invoked.

- **`opt_level`** — optimization level (e.g., 0–3)
- **`strip`** — strip debug symbols from the binary

Additional profile options can be added as the compiler's optimization passes mature.

---

## 5. Content-Addressed Store (CAS) Integration

March has a fully implemented CAS (`lib/cas/`) using BLAKE3 hashing with two-tier storage. Forge integrates with this existing system rather than building its own.

### 5.1 Storage Tiers

- **Local store:** `.march/cas/` (per-project)
- **Global store:** `~/.march/cas/` (shared across all projects)

### 5.2 How CAS Keys Are Computed

A build artifact's CAS key is the BLAKE3 hash of its inputs:

```
source code + locked dep SHAs + compiler version + profile flags → BLAKE3 → CAS key
```

This means identical inputs always produce the same CAS key, enabling:

- Incremental builds (only recompile what changed)
- Cross-project caching via the global store
- Instant rollback (reverting `forge.lock` hits the old cache entry)

### 5.3 Dependency Source in CAS

Dependency source code is itself stored in the CAS. When a dependency is fetched from git, its source snapshot is hashed and stored in the global CAS (`~/.march/cas/`).

**Key requirement:** If a dependency at a given commit already exists in the global CAS, pulling it into a project requires zero outbound network calls. Two projects sharing the same dep at the same commit share the same CAS entry.

---

## 6. Dependency Resolution and `forge.lock`

### 6.1 Resolution Flow

1. Developer declares deps in `forge.toml` (git URL or local path)
2. `forge deps` resolves each dep — for git deps, this means resolving to a specific commit SHA
3. Source is fetched and stored in the global CAS (`~/.march/cas/`)
4. Resolved SHAs are written to `forge.lock`
5. On subsequent builds, `forge.lock` is the source of truth — no network calls if the CAS already has the content

### 6.2 `forge.lock` Format

```toml
[deps.http]
git = "https://github.com/user/march-http.git"
commit = "a1b2c3d4e5f6789..."
cas_hash = "blake3:..."

[deps.json]
path = "../march-json"
cas_hash = "blake3:..."
```

### 6.3 Updating a Dependency

1. Run `forge deps update http`
2. Forge fetches the latest commit from the git remote
3. New source snapshot is hashed and stored in the CAS
4. `forge.lock` is updated with the new commit SHA and CAS hash
5. Next `forge build` computes a new CAS key (different inputs → different hash → fresh compile)
6. The old CAS entry remains cached — reverting `forge.lock` restores the old build instantly

### 6.4 Lock File Policy

`forge.lock` should be checked into version control for `app` and `tool` projects (reproducible builds across the team). For `lib` projects, checking in `forge.lock` is optional — library consumers will resolve their own dependency tree.

---

## 7. Build Output

All compiled artifacts live in `.march/build/`, organized by profile:

```
.march/
├── cas/                       # content-addressed store
└── build/
    ├── debug/                 # default build output
    └── release/               # --release build output
```

This keeps everything under one gitignored directory. `forge clean` wipes `.march/build/`, `forge clean --cas` also prunes `.march/cas/`, and `forge clean --all` removes the entire `.march/` directory.

---

## 8. Generated `.editorconfig`

All templates generate a `.editorconfig` for consistent editor behavior:

```ini
root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.march]
indent_size = 2
```

Natively supported by VS Code, all JetBrains IDEs, GitHub's web editor, Vim/Neovim, Sublime Text 4, and Nova. Widely available as a plugin for Emacs and older editors.

---

## 9. Generated `.gitignore`

```
/.march/
```

This covers both the CAS store and build artifacts. To be revisited if other generated files emerge that need ignoring.

---

## 10. Future Work

The following items are noted for future design but are explicitly out of scope for the initial implementation:

- **Compile-time environment variables** — A mechanism to bake environment variables into the compiled binary at build time (similar to Rust's `env!()` macro or Elixir's compile-time config). Needs language-level support.

- **Package registry** — A centralized registry for publishing and discovering March packages (like crates.io or hex.pm). For now, dependencies are git URLs and local paths.

- **Test framework** — The test syntax, assertion library, and test runner are a separate design effort. `forge test` provides the discovery and execution harness; the framework plugs into it.

- **CI templates** — Not generated by `forge new` initially. May be added later as optional flags (e.g., `forge new --ci github`).

- **LSP configuration** — The `march-lsp` language server is already implemented. `forge new` could generate editor-specific config files (e.g., `.vscode/settings.json`, `.zed/settings.json`) pointing to the `march-lsp` binary.

- **Dependency version resolution** — Full dependency tree solving with semver constraints, conflict resolution, and diamond dependency handling. Required before a package registry can exist. The current git URL + local path model defers this complexity intentionally.

---

## Appendix A: Command Quick Reference

```
forge new <name> [--app|--lib|--tool]   Create a new project (default: --app)
forge build [--release]                  Compile the project
forge run                                Build and execute
forge test                               Run tests in test/
forge format [--check]                   Format source code
forge interactive | forge i              Launch REPL
forge deps [update <name>]               Manage dependencies
forge clean [--cas|--all]                Remove build artifacts
```

## Appendix B: `forge.toml` Full Example

```toml
[project]
name = "my_web_app"
version = "0.1.0"
description = "A web application built with March"
type = "app"
march = "0.1.0"

[deps]
http = { git = "https://github.com/user/march-http.git" }
json = { path = "../march-json" }
router = { git = "https://github.com/user/march-router.git", rev = "v2" }

[dev-deps]
mock = { git = "https://github.com/user/march-mock.git" }

[profile.release]
opt_level = 3
strip = true
```
