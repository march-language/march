---
layout: docs
title: Tooling
nav_order: 15
permalink: /docs/tooling/
---

# Tooling

March ships with a build tool, an LSP server, and a tree-sitter grammar for editor syntax highlighting.

---

## Installing forge

After cloning and building the repo, install `forge` to your PATH with:

```sh
dune build && dune install forge
```

Then all forge commands are available directly:

```sh
forge run my_program.march
forge test
forge search "map"
```

---

## forge — Build Tool

`forge` is the official project manager for March.

### Creating a Project

```sh
forge new my_app           # application project (default)
forge new my_lib --lib     # library project
forge new my_tool --tool   # CLI tool project
cd my_app
```

Scaffolded layout:
```
my_app/
├── forge.toml          # project manifest
├── src/
│   └── my_app.march    # entry point (mod MyApp do ... end)
└── test/
    └── my_app_test.march
```

`forge.toml`:
```toml
[package]
name = "my_app"
version = "0.1.0"

[dependencies]
# add deps here
```

To add a `forge.toml` to an existing directory without scaffolding:

```sh
forge init
```

### Building and Running

```sh
# Build the project
forge build

# Build in release mode (optimized)
forge build --release

# Build and run
forge run

# Run with arguments
forge run -- --port 8080

# Compile to native binary via LLVM (instead of the interpreter)
forge run --compiled

# Dump compiler IR phases to trace/phases/phases.json
forge build --dump-phases
forge run --dump-phases

# Fail if forge.lock is out of sync with forge.toml
forge build --frozen
```

In a workspace, build a single member:

```sh
forge build -p my_lib
```

### Checking Types

`forge check` typechecks every `.march` file in the project without producing a binary. It's fast — use it for pre-commit checks or continuous editor feedback:

```sh
forge check
```

This catches type errors in every file under `lib/` (including orphaned modules that aren't reachable from the entry point), without paying for codegen or linking.

### Testing

```sh
# Run all tests
forge test

# Run tests matching a filter
forge test --filter "list operations"

# Show each test name as it runs
forge test --verbose

# Run a specific test file
forge test test/parser_test.march

# Property tests: run with a fixed seed (for reproducibility)
forge test --seed 42

# Skip property-based tests (Check.all)
forge test --skip-properties

# Collect and report coverage
forge test --coverage

# Compile test binary at -O2 (slower build, faster runtime)
forge test --release
```

### Linting

`forge lint` runs the March coding-standard rule engine across all source files:

```sh
forge lint               # report errors and warnings
forge lint --strict      # treat warnings as errors; exit 1 on any finding
forge lint --all         # also report hint-level findings
```

Rules are configurable via `.march-lint.toml` at the project root:

```toml
[rules]
snake_case_functions = "error"
unused_let           = "warning"
missing_doc          = "off"
```

### Watch Mode

`forge watch` reruns a command whenever a source file changes. It never exits on failure — it reports and keeps watching. Press Ctrl-C to stop.

```sh
forge watch            # rebuild on change (default)
forge watch test       # rerun tests on change
forge watch run        # rerun the app on change

forge watch --clear    # clear the screen before each run
forge watch --interval 500   # poll every 500 ms (default: 300 ms)
```

### Formatting

```sh
forge format                # format all .march files
forge format --check        # check without modifying (for CI)
forge format --stdin        # read from stdin, write to stdout (editor integration)
```

### Cleaning Build Artifacts

```sh
forge clean           # remove build outputs under .march/build/
forge clean --cas     # also remove the content-addressable cache (.march/cas/)
forge clean --all     # remove the entire .march/ directory
```

### Interactive Mode (REPL)

```sh
forge interactive
# alias:
forge i
```

---

## forge search — Hoogle-style Search

`forge search` lets you find functions by name, type signature, or documentation keyword.

### Search by Name

```sh
forge search "map"
# Finds: List.map, Map.map_values, Option.map, Result.map, ...

forge search "fold"
# Finds: List.fold_left, List.fold_right, Map.fold, Enum.fold, ...
```

### Search by Type Signature

```sh
forge search --type "List(a) -> (a -> b) -> List(b)"
# Finds: List.map, Enum.map

forge search --type "Option(a) -> a -> a"
# Finds: Option.unwrap_or

forge search --type "String -> Int"
# Finds: String.length, String.to_int (partial)
```

### Search by Documentation Keyword

```sh
forge search --doc "sort"
# Finds functions with "sort" in their docstrings

forge search --doc "hash"
```

### Output Options

```sh
forge search "map" --limit 5      # cap results (default: 20)
forge search "map" --json         # JSON output
forge search "map" --pretty       # colored, aligned table
```

### Rebuilding the Search Index

```sh
forge search --rebuild
```

The search index is cached at `.march/search-index.json` and rebuilt when source changes.

---

## forge cap — Capability and typestate inspection

`forge cap query` prints a capability and typestate summary across all `.march` files in your project. It parses (but does not typecheck) each file and reports every `needs`, `always_linear type`, `transitions`, and `proof cap` declaration.

```sh
forge cap query              # scan the whole project
forge cap query --dir lib/   # scan a specific directory
```

Example output for a project with a typestate database handle:

```
./lib/db.march
  needs:
    IO.Network
  always_linear:
    Handle
  transitions:
    Handle:
      ConnTag: Closed -> Open  via connect
      ConnTag: Open -> Open    via query
      ConnTag: Open -> Closed  via close
  proof_caps:
    Migrated

./lib/auth.march
  needs:
    IO.Network
    Db.Migrated
```

This gives you a top-level map of what your codebase touches and what resource lifecycles it manages — useful during code review, security audits, or onboarding a new contributor.

---

## Dependency Management

### Adding Dependencies

Use `forge add` to add a dependency without manually editing `forge.toml`:

```sh
# Git dependency (pinned to a tag)
forge add depot --git https://github.com/march-language/depot --tag v1.2.0

# Git dependency (tracked branch)
forge add depot --git https://github.com/march-language/depot --branch main

# Git dependency (exact commit)
forge add depot --git https://github.com/march-language/depot --rev a3f1c9b

# Local path dependency
forge add my_lib --path ../my_lib

# Dev dependency (available in dev + test builds)
forge add check --git https://github.com/march-language/check --tag v0.3.0 --dev

# Test-only dependency
forge add fixtures --path ../fixtures --test

# Overwrite an existing dependency entry
forge add depot --git https://github.com/march-language/depot --tag v1.3.0 --force
```

Or edit `forge.toml` directly:

```toml
[dependencies]
depot = { git = "https://github.com/march-language/depot", tag = "v1.2.0" }
```

Then resolve:

```sh
forge deps
```

### Updating Dependencies

```sh
forge deps update
forge deps update depot   # update a specific package
```

### Lock File

`forge.lock` pins exact versions for reproducible builds. Commit it to version control.

### Semver Constraints

| Syntax | Meaning |
|--------|---------|
| `~> 1.2` | `>= 1.2.0, < 2.0.0` |
| `~> 1.2.3` | `>= 1.2.3, < 1.3.0` |
| `>= 1.0.0` | At least 1.0.0 |
| `= 1.2.3` | Exactly 1.2.3 |

### Dependency Tree

```sh
forge tree         # print the full dependency graph
forge why depot    # show all paths that pull in `depot`
```

---

## Refactoring

`forge refactor` provides project-wide, parser-based refactorings. All subcommands accept `--dry-run` / `-n` to preview changes without writing any files.

### Rename a Symbol

```sh
# Rename a function, type, constructor, or any symbol
forge refactor rename old_name new_name

# Restrict to a specific kind (fn, type, ctor, module, field, var)
forge refactor rename Parser.parse Parser.run --kind fn

# Regex rename with backreferences
forge refactor rename 'get_(.+)' 'fetch_\1' --pattern
```

### Move a Declaration

```sh
# Move a top-level declaration to another file
forge refactor move MyParser lib/parser.march
```

### Structural Find-and-Replace

```sh
# Swap argument order at all call sites
forge refactor replace 'f($a, $b)' 'f($b, $a)'
```

### Apply Naming Conventions

```sh
# Auto-fix snake_case function names project-wide
forge refactor fix

# Preview without writing
forge refactor fix --dry-run
```

### Bundle Parameters into a Record

```sh
# Turn a function's parameters into a generated record type
forge refactor bundle parse_options
forge refactor bundle parse_options --record ParseConfig
```

---

## Documentation Generation

`forge doc` generates HTML documentation from March source files. It requires the `march_doc` archive:

```sh
forge install march_doc   # install once
```

Then:

```sh
forge doc                    # generate to doc/ (default)
forge doc -o docs/api        # custom output directory
forge doc --private          # include private (pfn) functions
forge doc --stdlib           # document stdlib only
```

---

## Notebooks

`forge notebook` provides a Livebook-style interactive environment for March using `.scrollmd` files. The live server requires the `scroll` archive:

```sh
forge install scroll   # install once
```

```sh
# Start a fresh notebook in the browser
forge notebook

# Open or create a specific notebook
forge notebook my_notes.scrollmd

# Start the live server explicitly
forge notebook my_notes.scrollmd --serve

# Render a notebook to static HTML
forge notebook my_notes.scrollmd -o output.html

# Use a custom port (default: 4040)
forge notebook --port 8080

# Don't open the browser automatically
forge notebook --no-open
```

---

## Versioning and Release

### Inspect and Bump Versions

```sh
forge version                # print current version
forge version patch          # bump patch: 1.2.3 -> 1.2.4
forge version minor          # bump minor: 1.2.3 -> 1.3.0
forge version major          # bump major: 1.2.3 -> 2.0.0
forge version 1.5.0          # set an explicit version

# Commit the bump and create an annotated git tag
forge version patch --tag
```

### Guarded Release Pipeline

`forge release` requires a clean working tree, then runs build → test → version bump → git tag in sequence. Any failure aborts before the tag is created:

```sh
forge release                # patch bump (default)
forge release --bump minor
forge release --bump major
```

### Publishing

`forge publish` validates the package and optionally checks that the version bump is correct given the API changes:

```sh
forge publish
forge publish --dry-run                          # validate only, don't submit
forge publish --old-source ../my_lib-v1.0        # enforce semver against old API surface
```

When `--old-source` is provided, forge computes the API surface diff and errors if the declared version bump is too small (e.g. a breaking change requires a major bump).

---

## Archive Management

Archives are globally installed forge extensions — tools, task runners, and generators.

```sh
# Install from the registry or a git URL
forge install march_doc
forge install scroll
forge install https://github.com/march-language/my_tool
forge install --force scroll     # reinstall even if already installed

# Remove an archive
forge uninstall march_doc

# List installed archives
forge archives

# Update installed archives
forge update                     # update all
forge update march_doc           # update one

# Verify archive integrity
forge verify                     # verify all
forge verify march_doc           # verify one
```

Archive tasks are invoked as `forge <archive>.<task>`:

```sh
forge march_doc.build    # run the `build` task of march_doc
```

---

## Toolchain Management

`forge toolchain` manages installed March compiler versions.

```sh
# List installed toolchains
forge toolchain list

# List available versions from GitHub releases
forge toolchain list --remote

# Install a specific version
forge toolchain install v0.3.0
forge toolchain install nightly          # latest nightly
forge toolchain install nightly-20251201

# Switch the active toolchain
forge toolchain use v0.3.0

# Pin this project to a specific version (writes .march-version)
forge toolchain pin v0.3.0

# Show which toolchain resolves for the current directory
forge toolchain which

# Remove an installed toolchain
forge toolchain uninstall v0.2.0

# Install the latest stable and make it active
forge upgrade
```

---

## License Audit

```sh
forge licenses             # list each dependency and its declared license
forge licenses --json      # JSON output for tooling
forge licenses --strict    # exit non-zero if any dependency has no license
```

---

## Capability Inspection

`forge cap query` performs a static analysis pass over the project and summarizes all capability and typestate declarations:

```sh
forge cap query                 # scan the project root
forge cap query --dir lib/      # scan a specific directory
```

Output lists every `needs`, `always_linear type`, `transitions`, and `proof cap` declaration found in the source, by file.

---

## Shell Completions

Generate a completion script for your shell and source it:

```sh
forge completions bash >> ~/.bashrc
forge completions zsh  >> ~/.zshrc
forge completions fish > ~/.config/fish/completions/forge.fish
```

---

## LSP Server

March ships `march-lsp`, a Language Server Protocol server built on the
compiler's own parse/typecheck pipeline, so diagnostics, hover types, and
completions are always accurate. It provides diagnostics, hover, go-to-definition
and find-references (cross-file), completions with auto-import, a large
code-action suite, rename, signature help, inlay hints, semantic tokens, call
hierarchy, workspace symbols, and per-function performance insights. A Debug
Adapter Protocol server (`march dap`) and a standalone JSON query CLI ship
alongside it.

**See the dedicated [LSP & Editors]({{ site.baseurl }}/docs/lsp/) page** for the full feature list,
per-editor setup (Neovim, Helix, Zed, Emacs, VS Code), the `march-lsp query`
CLI, and the DAP debugger.

---

## Zed Editor

March ships a tree-sitter grammar for Zed with syntax highlighting and bracket matching.

### Installing the Extension

The grammar is at `tree-sitter-march/` in the repository. In Zed:

1. Open the command palette: `Cmd+Shift+P`
2. Search for "Install Dev Extension"
3. Point to `tree-sitter-march/`

Alternatively, the compiled `march.dylib` can be installed directly into Zed's extension directory.

### What's Highlighted

- Keywords: `fn`, `pfn`, `let`, `match`, `do`, `end`, `mod`, `actor`, `on`, `type`, etc.
- String literals and interpolation (`${}`)
- Comments (`--` and `{- -}`)
- Operators and punctuation
- Type annotations
- Constructors (capitalized identifiers)
- Atoms (`:name`)

---

## Time-Travel Debugger

Place a `dbg()` breakpoint anywhere in your code:

```elixir
fn process(items : List(Int)) : Int do
  let filtered = List.filter(items, fn x -> x > 0)
  dbg()    -- breakpoint: REPL opens here
  let result = List.fold_left(0, filtered, fn acc x -> acc + x)
  result
end
```

When execution reaches `dbg()`, the program pauses and enters debug mode:

```
[debug] Breakpoint hit — :continue to resume, :help for commands

dbg> :where
process  examples/debug.march:5
main     examples/debug.march:12

dbg> filtered
[1, 3, 5] : List(Int)

dbg> :back 2
-- stepped back 2 steps

dbg> :continue
-- resuming...
```

Debug REPL commands:
```
:continue           — resume execution
:back N             — step N steps backward in time
:forward N          — step N steps forward
:goto N             — jump to step N
:where              — show current call stack
:diff N [names]     — show what changed at step N
:find               — search for a step matching a condition
:trace N            — show N steps of execution trace
:actors             — list all actors and their state history
:actor ID           — show a specific actor's message history
```

The debugger captures a full execution trace including all actor message sends and receives.

---

## Compiler Analysis

### Dumping IR Phases

Add `--dump-phases` to any build or run command to serialize each compiler IR stage to `trace/phases/phases.json`:

```sh
forge build --dump-phases
forge run --dump-phases
```

To compile a single `.march` file and dump phases (without a forge project):

```sh
forge compile my_program.march
```

This compiles the file, writes the binary to `.forge/compile/my_program`, and writes phases to `trace/phases/phases.json`.

### Viewing Phases in the Browser

```sh
forge phases          # serve phase viewer at http://localhost:7777
forge phases --port 8888
```

`forge phases` opens the browser automatically and serves an interactive viewer showing:
- Per-function TIR dumps at each compiler pass
- Inline eligibility and reasoning
- RC density visualization (which values are reference-counted most)

### Analyzing GC Traces

```sh
MARCH_TRACE_GC=1 forge run my_program.march
```

With `MARCH_TRACE_GC=1` set, the runtime logs all reference-counting operations to `trace/gc/gc.jsonl`. The analysis command reports:
- Leaked objects (allocated but never freed)
- Double frees
- Negative reference counts (invariant violations)

Open `tools/gc-viewer.html` after running with `MARCH_TRACE_GC=1`:
- Timeline of alloc/free/inc_ref/dec_ref events
- Live-object count chart
- Address history for any specific object

### Benchmarking

```sh
forge bench                   # run all benchmarks under bench/
forge bench list_ops          # run only benchmarks whose name contains "list_ops"
forge bench --json            # emit timings as JSON (for CI tracking)
```

Each `bench/*.march` file is a standalone benchmark program with a `main()` function. Benchmarks are compiled at `-O2` and timed.

---

## Environment Variables

| Variable | Effect |
|----------|--------|
| `MARCH_LIB_PATH` | Colon-separated paths for multi-file project discovery |
| `MARCH_TRACE_GC` | Set to `1` to log GC events to `trace/gc/gc.jsonl` |
| `MARCH_HISTORY_FILE` | REPL history file path (default: `~/.march_history`) |
| `MARCH_HISTORY_SIZE` | Max REPL history entries (default: 1000) |
| `MARCH_ENV` | `development` / `test` / `production` (read by `Config.env`) |

---

## Next Steps

- [Getting Started](getting-started.md) — set up your first project with forge
- [REPL](repl.md) — interactive exploration
- [Standard Library](stdlib.md) — what you can search with `forge search`
