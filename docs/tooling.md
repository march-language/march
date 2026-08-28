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
forge build
forge test
forge search "map"
```

---

## forge: Build Tool

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
├── lib/
│   └── my_app.march    # entry point (mod MyApp do ... end)
└── test/
    └── my_app_test.march
```

`forge.toml`:
```toml
[package]
name = "my_app"
version = "0.1.0"

[deps]
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

### JavaScript Backend

March compiles to ES modules with `--target js`. The output is a self-contained `.mjs` file that runs in Node.js or any modern browser:

```sh
# Compile to ES module
march --target js -o dist/app.mjs src/app.march

# Copy the runtime alongside the output (default; omit --no-copy-runtime)
march --target js -o dist/app.mjs src/app.march
# → dist/app.mjs + dist/march_runtime.mjs + dist/march_dom.mjs

# Run with Node
node dist/app.mjs

# Skip runtime copy (e.g. build tool manages it)
march --target js --no-copy-runtime -o dist/app.mjs src/app.march
```

The JS backend auto-loads `dom.march` from stdlib, so `Js.Dom.*` functions are available without any extra imports in JS builds:

```march
mod Counter do
  fn main() : Unit do
    match Js.Dom.find("counter") do
      None    -> ()
      Some(el) ->
        Js.Dom.set_text(el, "0")
        Js.Dom.listen(el, "click", fn _ -> Js.Dom.set_text(el, "clicked!"))
    end
  end
end
```

In HTML, import the output as an ES module:

```html
<script type="module" src="dist/app.mjs"></script>
```

The `Js.Dom` module is JS-only: calling DOM functions in a native build is a compile-time error at the capability level, but a runtime panic if you bypass the type system with FFI.

#### forge build and watch with --target js

`forge build` and `forge watch` both accept `--target js`:

```sh
forge build --target js          # compile → .march/build/debug/<name>.mjs
forge watch --target js          # rebuild on change
forge watch run --target js      # rebuild + re-run with node on change
```

#### JS FFI: calling npm packages

Import any npm package via an `extern` block. Use the bare npm package name (no `npm:` prefix; Node.js resolves those directly):

```march
mod App do
  needs IO.Foreign
  extern "lodash" : Cap(IO.Foreign) do
    fn chunk(arr: List(String), size: Int) : List(List(String)) = "chunk"
  end
end
```

Declare npm dependencies in forge.toml under `[js_deps]`. `forge build --target js` will write a `package.json` and run `npm install` automatically:

```toml
[js_deps]
lodash = "^4.17.21"
react  = "^18.3.0"
```

The generated `package.json` sets `"type": "module"` so your `.mjs` output loads cleanly. For Deno or Bun, use their native specifiers (`npm:lodash`, `jsr:@std/path`) directly in the `extern` lib name; no `[js_deps]` needed since those runtimes fetch packages on demand.

### Cross-compiling to Linux

March can build a **Linux** binary from any host (including macOS) the way Go's
`GOOS=linux go build` does. Pass a `linux/*` target and you get a native Linux
ELF without a Linux box, VM, or Docker build step:

```sh
march --compile --target linux/amd64 app.march -o app   # x86-64 Linux
march --compile --target linux/arm64 app.march -o app   # aarch64 Linux

forge build --target linux/amd64                          # via forge
forge build --target linux/arm64
```

Accepted aliases: `linux/amd64` (= `linux/x86_64`) and `linux/arm64`
(= `linux/aarch64`).

**Prerequisite: `zig`.** Cross-compilation uses [`zig cc`](https://ziglang.org)
as the C cross-compiler (it bundles a clang plus the Linux sysroots, so there's
no further install step). Put `zig` on your `PATH`:

```sh
brew install zig          # macOS
# or download from https://ziglang.org/download/
```

`forge build --target linux/…` checks for `zig` up front and tells you if it's
missing; a bare `march --compile --target linux/…` will fail at the link step
without it.

**Output.** `forge` writes cross builds to a per-target directory so they never
clobber your host binary:

```
.march/build/linux-amd64/debug/<name>
.march/build/linux-arm64/release/<name>
```

**What you get.** A **dynamically-linked glibc** binary (minimum glibc 2.31,
Ubuntu 20.04 / Debian 11 and newer). It runs on mainstream distributions and in
glibc-based containers (`debian:*-slim`, `ubuntu:*`, distroless-cc), e.g.:

```dockerfile
FROM debian:bookworm-slim
COPY app /usr/local/bin/app
CMD ["app"]
```

```sh
# Smoke-test a cross build locally, without deploying:
march --compile --target linux/amd64 app.march -o app
docker run --rm --platform linux/amd64 -v "$PWD/app":/app:ro debian:bookworm-slim /app
```

**Scope (current).** Cross-compilation currently targets **compute and CLI
workloads**. Not yet included in a cross build:

- **TLS/HTTPS** and **compression** (zstd/brotli/zlib): these runtime modules are
  omitted from cross builds for now.
- **Hot code reload**: the reload `.so` path is host-only today; deploy a
  pre-built artifact instead (see [Hot Code Reload](hot-code-reload.md)).
- **Rust FFI** (`[ffi.rust]`): `forge build --target linux/…` fails with a clear
  message rather than mislinking a host-architecture static library.
- **Concurrency/actor programs** are not yet validated on cross targets.

Correctness is guarded by a differential test that cross-compiles a corpus and
checks each program's output against the native build to the exact byte, so a
codegen regression on a cross target is caught in CI.

### Checking Types

`forge check` typechecks every `.march` file in the project without producing a binary. It's fast; use it for pre-commit checks or continuous editor feedback:

```sh
forge check
```

This catches type errors in every file under `lib/` (including orphaned modules that aren't reachable from the entry point), without paying for codegen or linking.

### Auto-fixing Diagnostics

`forge fix` reads compiler warnings and applies mechanically-determined fixes automatically: no human judgment needed, no ambiguity. It's the equivalent of `cargo fix` or `eslint --fix`.

```sh
forge fix              # apply all auto-fixable warnings in the project
forge fix --dry-run    # show what would change without writing any files
```

**What it fixes:**

| Warning | Fix |
|---|---|
| Missing `needs X` declaration | Inserts `needs X` after the `mod Name do` opening line |
| Unused `needs X` declaration | Deletes the `needs X` line |
| Unused function parameter | Prefixes the parameter name with `_` |
| Redundant (unreachable) match arm | Deletes the entire arm (pattern + body) |

`forge fix` will not apply any fixes if the project has errors; fix those first. It only touches files inside your project root, applies edits bottom-up so earlier line offsets stay valid, and deduplicates identical fixes before writing.

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

`forge watch` reruns a command whenever a source file changes. It never exits on failure; it reports and keeps watching. Press Ctrl-C to stop.

```sh
forge watch                     # rebuild on change (default)
forge watch test                # rerun tests on change
forge watch run                 # rerun the app on change

forge watch --target js         # rebuild .mjs on change
forge watch run --target js     # rebuild + re-run with node on change

forge watch --clear             # clear the screen before each run
forge watch --interval 500      # poll every 500 ms (default: 300 ms)
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

## forge search: Hoogle-style Search

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
# Finds: String.byte_size, String.to_int (partial)
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
forge search "map" --plain        # plain text, no colors (for piping or LLM use)
```

### Rebuilding the Search Index

```sh
forge search --rebuild
```

The search index is cached at `.march/search-index.json` and rebuilt when source changes.

---

## AI assistant search: spec-search Claude Skill

`forge search` (above) finds *code*: functions, types, signatures. `spec-search`
is its counterpart for *documentation*: a Claude Code skill that full-text
searches March's language reference (`specs/lang/`), internals reference
(`specs/impl/`), and feature design docs (`specs/features/`), roughly 44
files, 20-25k lines, via a bundled SQLite [FTS5](https://sqlite.org/fts5.html)
index.

It's fully self-contained: the markdown docs and the prebuilt index ship
*inside* the skill directory, so it works in any March project, not just a
checkout of the compiler repo.

### Installing

Install once, at the user level, and it's available to Claude in every
project on the machine:

```bash
git clone https://github.com/march-language/march.git
mkdir -p ~/.claude/skills
cp -R march/.claude/skills/spec-search ~/.claude/skills/spec-search
```

(Vendoring a copy into a specific project's own `.claude/skills/` instead
also works, if you want that project pinned to a particular spec snapshot;
the directory is self-contained either way.)

### Using it

Claude invokes the skill automatically for March language/design questions
that go beyond syntax basics: actor supervision semantics, refinement
types, session types, capabilities, module resolution, etc. You can also
run the query script directly:

```bash
~/.claude/skills/spec-search/spec-search.sh "actor supervision restart"
~/.claude/skills/spec-search/spec-search.sh --json -n 5 "refinement predicate"
```

Output is ranked by relevance (SQLite's `bm25()`), one hit per matched
markdown section (file, heading path, line range, and a highlighted
snippet), so answers are grounded in a precise slice of the docs rather
than a whole 1000-line chapter.

### Rebuilding the index

Run this from a clone of the [march-language/march](https://github.com/march-language/march)
repo after `specs/lang/`, `specs/impl/`, or `specs/features/` change:

```bash
./scripts/build-spec-index.sh
```

This vendors the current docs and rebuilds `.claude/skills/spec-search/spec-search.db`
in place. Review the diff, commit it, then re-copy the directory to
`~/.claude/skills/spec-search/` to pick up the change. The index includes a
`meta` table stamping the source commit and build date; check it if search
results look out of date:

```bash
sqlite3 ~/.claude/skills/spec-search/spec-search.db "SELECT * FROM meta;"
```

---

## forge refine: Suggest a refinement type

`forge refine <fn>` proposes the parameter refinement that discharges the
refinement obligations a function's body leaves unproven. If `n` is passed to a
callee declaring `{Int | _ > 0}`, the contract `n` itself has to carry is the
thing the tool works out for you:

```sh
forge refine split           # one function (bare or qualified name)
forge refine split --apply   # write the annotation into the source
forge refine --all           # sweep every function in the project
forge refine --all --apply --fixpoint   # …and keep going until nothing changes
```

A contract only becomes visible to a *caller* once the callee bears it, so one
`--apply` pass propagates exactly one call hop. `--fixpoint` repeats until a round
applies no change (bounded at 10 rounds; hitting the bound is reported as such, not
mistaken for convergence).

```
lib/text.march:10  split
    n : Int  ->  n : {Int | _ > 0}
  discharges all 1 unproven obligation(s)
```

**A suggestion is never a guess.** Each candidate is hypothesised onto the
signature and the *real* refinement checker is re-run over the function; the
candidate is proposed only if the checker discharges obligations under it and
introduces no new violation. So `march check` after `--apply` agrees with what
was printed, and there is no second implementation of the prover to drift.

When several candidates work, the **weakest** wins: a divisor contract is
reported as `_ != 0` rather than `_ > 0`, so accepting the suggestion does not
invisibly reject callers the function would have accepted.

Silence is never ambiguous. Every function reports one of:

| Outcome | Meaning |
|---|---|
| a proposal | the listed annotations discharge the listed obligations |
| `nothing to prove` | the body has no unproven obligation |
| `no candidate…` | there is debt, but no candidate in the grammar shifts it |
| partial | some obligations discharged; the rest are counted |
| `search stopped at the probe budget…` | the search was **truncated**, not exhausted; raise `--budget` and ask again |

**A contract that contradicts the function is not proposed.** A `_safe` wrapper that
matches `Nil -> Err(...)` and does the real work in the other arm bears real
unproven debt, and `{List(a) | len(_) > 0}` would discharge it, by forbidding the
exact input the function exists to accept. `forge refine` suppresses that: if the
function handles the excluded case **non-fatally**, no contract is proposed. If it
handles it by **panicking**, the contract still is; turning that panic into a compile
error is the whole point.

The candidate grammar covers sign and non-zero contracts on `Int` and `Float`,
`len(_) > 0` on `List`/`String`, and index contracts (`_ >= 0 && _ < len(xs)`)
against each list or string parameter in the same signature. A parameter with
no type annotation, or one that is already refined, is left as-is.

Requires Z3 on `PATH`, like the rest of refinement checking. `--budget N` caps
how many hypothesis re-checks the inference may spend **per function** (default
200), so a `--all` sweep cannot have its answers silently truncated by whichever
functions happen to be visited first.

In an editor, the same inference is available as the **"Suggest a refinement
type for `f`"** code action on a function's name; accepting it applies the
identical edit.

---

## forge cap: Capability and typestate inspection

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

This gives you a top-level map of what your codebase touches and what resource lifecycles it manages, useful during code review, security audits, or onboarding a new contributor.

`forge cap coverage` reports which of the capabilities your project possesses are exercised by tests and which are not (a `Covered` / `Uncovered` list and an `N/M capabilities covered (X%)` summary), so a capability that no test exercises is easy to spot.

### Reading and enforcing a compiled binary

The subcommands above read source. Two more work on a built artifact:

```sh
forge cap inspect ./build/myapp                          # what capabilities does this binary hold?
forge cap inspect ./build/myapp --deny IO.Network         # fail if it holds IO.Network (repeatable)
forge cap inspect ./build/myapp --allow-only IO.Console    # fail if it holds anything outside this set
forge cap run ./build/myapp                               # run it under a sandbox forge installs
forge cap run --allow-only IO.Console ./untrusted          # run untrusted code with a policy YOU choose
```

`forge cap inspect` cross-checks capability markers the compiler emitted, capability-bearing runtime symbols that persisted through dead-stripping, and an embedded manifest when present; `--deny`/`--allow-only` are **fail-closed** (they fail on a binary with coverage that is not full, and foreign code requires `--allow-foreign`). `forge cap run` is the enforcing counterpart: it launches the binary under an OS sandbox before the program gets control. Both are covered in depth on the [Capability Audit](capability-audit.md) page and under [OS-level enforcement]({{ site.baseurl }}/docs/capability-enforcement/#os-level-enforcement-sandboxing-the-compiled-binary); a binary can also sandbox *itself* at startup when compiled with `march --compile --cap-sandbox`.

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
[deps]
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

## Hot Code Reload

`forge deploy hot` deploys new code to a running server without restarting the process. Actors keep running and their state is preserved; only changed functions are uploaded and activated.

```sh
# Build and deploy to the configured remote server
forge deploy hot

# Deploy a pre-built artifact (e.g. cross-compiled for Linux)
forge deploy hot --so /path/to/my_app.so
```

Configure the target server in `forge.toml`:

```toml
[hot-reload]
ssh_host   = "my-server"      # SSH host alias
socket     = "/tmp/app.sock"  # Unix socket path on the remote
public_key = "base64key="     # ed25519 public key
```

When actor state changes, provide a `<actor>_migrate_state` function to upgrade live actors. If the actor bears an `@invariant`, the compiler verifies the migration preserves it before anything is uploaded.

See [Hot Code Reload]({{ site.baseurl }}/docs/hot-code-reload/) for the full guide.

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

Archives are globally installed forge extensions: tools, task runners, and generators.

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

```march
fn process(items : List(Int)) : Int do
  let filtered = List.filter(items, fn x -> x > 0)
  dbg()    -- breakpoint: REPL opens here
  let result = List.fold_left(filtered, 0, fn (acc, x) -> acc + x)
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

- [Getting Started](getting-started.md): set up your first project with forge
- [REPL](repl.md): interactive exploration
- [Standard Library](stdlib.md): what you can search with `forge search`
