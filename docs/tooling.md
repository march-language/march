---
layout: docs
title: Tooling
nav_order: 15
permalink: /docs/tooling/
---

# Tooling

`forge` is March's project tool: it creates, builds, runs, tests, lints and formats a
project, manages its dependencies and toolchains, searches the standard library, and
deploys and observes a running node. Beside it March ships `march-lsp`, a language
server built on the compiler's own pipeline, a tree-sitter grammar for editors, a
time-travel debugger, and the compiler's own analysis commands.

This page is the command reference. Each section is one command or one family of
commands with its flags and what they do; the index below groups them by what you are
trying to do, and the table after it goes from a task to the command.

## On this page

**Start here**

- [Installing forge](#installing-forge)
- [Which command do I need?](#which-command-do-i-need)
- [How it fits with the rest of March](#how-it-fits-with-the-rest-of-march)

**Everyday**

- [forge: Build Tool](#forge-build-tool): [creating a project](#creating-a-project), [building and running](#building-and-running), [GUI apps](#gui-apps-main-on-the-process-main-thread), [JavaScript backend](#javascript-backend), [cross-compiling to Linux](#cross-compiling-to-linux), [static binaries](#static-binaries), [checking types](#checking-types), [asking the compiler questions](#asking-the-compiler-questions), [auto-fixing diagnostics](#auto-fixing-diagnostics), [testing](#testing), [linting](#linting), [watch mode](#watch-mode), [formatting](#formatting), [cleaning](#cleaning-build-artifacts), [REPL](#interactive-mode-repl)

**Finding things**

- [forge search: Hoogle-style Search](#forge-search-hoogle-style-search)
- [AI assistant search: spec-search Claude Skill](#ai-assistant-search--spec-search-claude-skill)

**Safety tooling**

- [forge refine: Suggest a refinement type](#forge-refine-suggest-a-refinement-type)
- [forge cap: Capability and typestate inspection](#forge-cap-capability-and-typestate-inspection)
- [Dependency Capability Audit](#dependency-capability-audit)
- [License Audit](#license-audit)

**Dependencies and toolchains**

- [Dependency Management](#dependency-management): [adding](#adding-dependencies), [updating](#updating-dependencies), [the lock file](#lock-file), [offline builds](#offline-builds), [semver](#semver-constraints), [the tree](#dependency-tree)
- [Archive Management](#archive-management)
- [Toolchain Management](#toolchain-management)

**Changing and documenting code**

- [Refactoring](#refactoring)
- [Documentation Generation](#documentation-generation)
- [Notebooks](#notebooks)

**Deploying and operating**

- [forge topology: the topology file](#forge-topology-the-topology-file)
- [Hot Code Reload](#hot-code-reload)
- [forge observe: what a running node is doing](#forge-observe-what-a-running-node-is-doing)
- [Versioning and Release](#versioning-and-release): [bumping](#inspect-and-bump-versions), [the release pipeline](#guarded-release-pipeline), [release bundles](#release-bundles-forge-release-build), [publishing](#publishing)

**Editors and debugging**

- [LSP Server](#lsp-server)
- [Zed Editor](#zed-editor)
- [Time-Travel Debugger](#time-travel-debugger)
- [Compiler Analysis](#compiler-analysis)
- [Shell Completions](#shell-completions)

**Reference**

- [Environment Variables](#environment-variables)
- [See also](#see-also)

## Which command do I need?

| You want to | Run |
|---|---|
| Start a project | `forge new my_app`, or `forge init` in an existing directory |
| Build, run, test | `forge build`, `forge run`, `forge test`; add `--compiled` or `--release` for native builds |
| Typecheck without building | `forge check` |
| Rebuild on every save | `forge watch`, `forge watch test`, `forge watch run` |
| Apply the fixes the compiler already knows | `forge fix` |
| Find a function by name, type or docstring | `forge search "map"`, `forge search --type "List(a) -> (a -> b) -> List(b)"` |
| Understand what the compiler did to a function | `forge query fn Name`, `forge query origin`, `forge query why-miss` |
| Add a dependency, or see what it would newly be allowed to do | `forge add`, `forge audit`, `forge outdated` |
| Get refinement contracts proposed, or written | `forge refine --infer --diff`, `forge refine --infer --apply`; one function: `forge refine fn_name` |
| See what a binary may do, or run it in a sandbox | `forge cap inspect`, `forge cap run` |
| Rename or move a declaration across the project | `forge refactor rename`, `forge refactor move` |
| Build for Linux from a Mac | `forge build --target linux/amd64` |
| Compile to JavaScript | `march --target js` or `forge build --target js` |
| Deploy to a running server without restarting | `forge deploy hot`; with a topology, `forge deploy --env prod` |
| See what a running node is doing | `forge status`, `forge diagnose`, `forge top`, `forge observe` |
| Cut a release | `forge release`, `forge release build` |
| Switch compiler versions | `forge toolchain use`, `forge toolchain pin` |

## How it fits with the rest of March

| Concept | The tooling for it | Chapter |
|---|---|---|
| **Capabilities** | `forge cap query` and `inspect`, `forge cap run`, `forge audit`, and the `needs` lines `forge fix` inserts. | [Capabilities]({{ site.baseurl }}/docs/capabilities/), [Capability Audit](capability-audit.md), [Capability Enforcement]({{ site.baseurl }}/docs/capability-enforcement/) |
| **Refinement types** | `forge refine --infer` proposes and writes every contract the checker can verify; `--refine-report` and `--refine-audit` say what was checked. | [Refinement Types]({{ site.baseurl }}/docs/refinement-types/) |
| **Hot code reload and topology** | `forge deploy hot`, `forge deploy --env`, `forge host init`, `forge topology`. | [Hot Code Reload]({{ site.baseurl }}/docs/hot-code-reload/), [Topology](topology.md) |
| **Observing a running node** | `forge status`, `diagnose`, `top`, `observe`, `shell`. | [Observe](observe.md) |
| **Memory model** | `forge query repr`, `forge phases`, the GC trace viewer, and the editor's reuse hints. | [Memory Model]({{ site.baseurl }}/docs/memory-model/) |
| **Editors** | `march-lsp` features, per-editor setup, the DAP debugger. | [LSP & Editors]({{ site.baseurl }}/docs/lsp/) |
| **Testing** | `forge test` flags, property tests and seeds. | [Property Testing](property-testing.md) |

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

`forge` is the project manager. The subsections below cover the everyday commands.

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
forge run                        # run the project entry (interpreted)
forge run --compiled             # compile via LLVM, then run the binary
forge run foo.march              # run a single file
forge run --compiled foo.march   # compile and run a single file
forge run foo.march -- a b       # pass a and b to the program as its argv

# Dump compiler IR phases to trace/phases/phases.json
forge build --dump-phases
forge run --dump-phases

# Fail if forge.lock is out of sync with forge.toml
forge build --frozen
```

A file named on the command line still sees the surrounding project's modules
and FFI shims when it is inside a project, so a scratch file can import your own
code; outside a project it runs standalone. Arguments after `--` reach the
program as `System.argv()`, with `argv[0]` the script path when interpreted and
the binary path when compiled. Passing arguments requires naming a FILE.

#### GUI apps: `main` on the process main thread

Cocoa and GLFW only create windows from the process main thread. Setting
`pin_main` in `[package]` compiles the project with `march --pin-main`, so the
binary runs `main` there on its own, without `MARCH_PIN_MAIN=1` in the
environment (a double-clicked app has no such environment):

```toml
[package]
name = "my_gui_app"
version = "0.1.0"
pin_main = true   # unquoted boolean; default false
```

It applies to every command that compiles the project's program: `forge build`,
`forge run --compiled` (including a named FILE inside the project),
`forge bench` and `forge install`. It does not change `forge test`, whose
compiled test binary already runs every test on the process main thread, or
interpreted runs, which have no compiled entry point. Any value other than
`true` or `false`, including the quoted string `"true"`, is a `forge.toml`
error rather than a silent "off".

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

**`Int` is a subset on this target.** An `Int` is a JS number, exact only within ±(2^53 - 1). Inside that range arithmetic, division and the `int_*` bitwise builtins give the same answers as a native build. Past it, `+`, `-` and `*` round instead of wrapping at 63 bits, the `int_*` builtins throw a `RangeError`, and `int_max_value()`/`int_min_value()` do not compile. See [Int on the JavaScript target]({{ site.baseurl }}/docs/types/#int-on-the-javascript-target) for the full list.

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

### Static binaries

A compiled program links only the runtime libraries it uses: one that never uses TLS
does not load OpenSSL, and one that never uses `Compress` loads no compression library.
`--static` goes further and makes the binary self-contained:

```bash
march --compile --static app.march -o app
```

- **Linux:** a fully static executable with no shared-library dependencies, which runs in a
  `scratch` or distroless image. It links against musl, so it builds on a musl host such as
  Alpine (`apk add clang build-base openssl-dev openssl-libs-static zlib-static zstd-static
  brotli-static libucontext-dev`). On a glibc host it is refused: a static glibc binary
  still depends on the host for name-service lookups, iconv and `dlopen`.
- **macOS:** a fully static executable is not possible (`libSystem` is always dynamic), so
  `--static` means the binary loads nothing outside `/usr/lib` and `/System`. OpenSSL, zstd
  and brotli come from Homebrew's static archives, so the binary runs on a Mac without
  Homebrew.

The compiler checks the result after linking and refuses a binary that still loads a
library outside that set (for example through `--ffi-link`). A library the program needs
whose static archive is missing is an error naming the package to install. `--static`
cannot be combined with `--hot-reload` (hot patches are loaded with `dlopen`) or
`--compile-so`, and not yet with `--target`.

**TLS certificates.** A static binary carries no CA bundle. Point it at one with OpenSSL's
standard variables, `SSL_CERT_FILE` (a bundle file) or `SSL_CERT_DIR` (a directory), and copy
the bundle into a `scratch` image:

```dockerfile
FROM scratch
COPY --from=alpine:3.21 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY app /app
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENTRYPOINT ["/app"]
```

A binary that links OpenSSL statically contains it, so distribute OpenSSL's license
(Apache-2.0) with it; the compiler prints a reminder when it does.

### Checking Types

`forge check` typechecks every `.march` file in the project without producing a binary. It's fast; use it for pre-commit checks or continuous editor feedback:

```sh
forge check
```

This catches type errors in every file under `lib/` (including orphaned modules that aren't reachable from the entry point), without paying for codegen or linking.

### Asking the Compiler Questions

`forge query` asks the compiler one question about your project's build and prints the answer. It is for the moments `forge build` can't explain: why a function compiles to what it does, where a generated name came from, or why a build wasn't cached. It runs the compile up to the point it can answer, then stops. Nothing is built, linked, or written to the build cache.

```sh
forge query fn Server.handle                 # the passes that changed it, and its body at the last one
forge query fn Server.handle --at tir-perceus   # its body after one named pass
forge query origin 'Server.handle$apply$3'   # where an emitted function came from
forge query callers Server.handle            # who references it in the final IR
forge query callees Server.handle            # what it references
forge query repr Server.Conn                 # how each instance of a type is represented, and why
forge query verify                           # run the IR verifier over every compiler stage
forge query key                              # both build-cache keys and every input that fed them
forge query why-miss                         # which input changed since the last successful build
```

| Query | Answers |
|---|---|
| `fn NAME` | The passes that changed `NAME` and its specialisations, and its body after the last (or `--at PASS`) |
| `origin NAME` | Source span, host function, and the specialisation or lambda it derives from |
| `callers NAME`, `callees NAME` | The final call graph, one level |
| `repr TYPE` | Whether each instance of `TYPE` is boxed, unboxed, a niche, or a newtype, and the reason |
| `verify` | The compiler's internal consistency checks over every stage, as findings instead of a crash |
| `key` | The source-level and post-TIR cache keys, whether each is cached, and each input behind them |
| `why-miss` | Which input changed since the last successful build, and which cache layer the next build will hit |

With no file named, a query is about the project's entry file; name a `.march` file to ask about that one instead. `--json` prints one JSON object. `--release` and `--target T` ask about the build that `forge build --release` or `--target T` would run, and the project's library path, `[ffi]` flags, topology digest (once a build has written one) and protocol baselines are passed as `forge build` passes them. That is why `forge query key` agrees with a real build: after `forge build`, it reports the same post-TIR key as cached. Anything after `--` goes to the compiler unchanged:

```sh
forge query fn main -- --no-opt     # the same question, with the optimiser off
```

Two things to know when reading an answer:

- **A name the optimiser inlined is not in the final IR.** `fn` and `origin` then report the last stage that had it. Add `-- --no-opt` to keep it.
- **`why-miss` needs one successful build first.** It compares against the record of the last build of that file, so run `forge build` once and ask again.

A query never builds a `[ffi.rust]` crate, runs a preprocessor, writes a protocol baseline, or downloads a toolchain. A library project has no entry file, so name one: `forge query verify lib/parser.march`. Outside a project, `forge query verify FILE` works on a single file. `march query` is the same interface without the project: `march query fn NAME FILE`.

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

`forge refine --infer` proposes every refinement contract the checker can verify,
across the whole project, and with `--apply` writes them (see
[Infer every contract](#infer-every-contract-forge-refine---infer) below).
`forge refine <fn>` is the older, per-function form: it proposes the parameter
refinement that discharges the refinement obligations a function's body leaves
unproven. If `n` is passed to a
callee declaring `{Int | _ > 0}`, the contract `n` itself has to carry is the
thing the tool works out for you:

```sh
forge refine split           # one function (bare or qualified name)
forge refine split --apply   # write the annotation into the source
forge refine --all           # sweep every function in the project
```

A contract only becomes visible to a *caller* once the callee bears it, so one
`--all --apply` pass propagates exactly one call hop. Pass `--infer` to search to
a fixpoint instead (`--fixpoint` is now an alias of `--infer`).

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

### Infer every contract: `forge refine --infer`

```sh
forge refine --infer                    # dry run: what it would propose, refuse, and why
forge refine --infer --diff             # the edits as a diff; nothing is written
forge refine --infer --apply            # write them, then re-check the project
forge refine --infer --apply --apply-public            # also public fns with no caller in the project
forge refine --infer --allow-caller-violations         # accept a precondition that breaks a caller
```

`--infer` covers every kind of refinement the checker can verify:
- scalar and relational preconditions (`b : {Int | _ != 0}`, `i : {Int | _ < n}`);
- return contracts, including one relating the result to a parameter (`inc(x : Int) : {Int | _ > x}`);
- element contracts (`xs : List({Int | _ > 0})`, element and tuple returns, each slot of a `Map`,
  `Deque.Deque`), and a relation between two slots a caller demands (`Assoc({x : Int | true}, {y : Int | y > x})`);
- abstract refinements for `filter`-shaped helpers (`pred : a -> Bool[p]` with `List(a[p])`, and
  two-argument `keep : k -> v -> Bool[p]` with `Assoc(k[p], v[p])`);
- fold accumulator invariants (`fold_left` and `fold_right` steps);
- termination metrics: `@[decreases(100 - n)]` for a recursive function the checker
  could not show to terminate, chosen from at most 8 candidates (each `Int` parameter,
  `b - i` for a counter climbing to a bound, `len(xs)`, and pairs of those), each
  checked at every recursive call. A metric for a local `fn` is shown but not written,
  since a local `fn` takes no attribute.

It searches to a fixpoint over the call graph in one run, callees first. Returns go before
preconditions: a proved return costs no caller anything, while a precondition moves the
obligation to every caller.

```
inferred refinements: 2 proposed, 0 refused; user skips 2 -> 0 (101 probes, 2 rounds)
  positives (lib/scores.march:8)  return/elem : List({Int | _ > 0})  [element-return, closes 1]
  report (lib/scores.march:12)  param n : {Int | _ > 0}  [precondition, closes 1]
inferred metrics: 1 proposed, 0 not inferred
  up (lib/scores.march:20)  @[decreases(100 - n)]  [termination, class B, 1 of 1 candidate checked]
applied 3 proposal(s) to 1 file(s); the re-check matches the prediction
```

A metric is written in front of the function's `fn`, on the same line
(`@[decreases(100 - n)] fn up(n : Int) : Int do`). A function no candidate works
for is listed as `no metric inferred`, with how many candidates were checked.

What each outcome means:

- **Proposed.** The real checker proves the contract, it closes at least one unproven
  obligation, and it opens none and creates no violation.
- **`refused (caller-violation)`.** A precondition that would turn an existing call into a
  violation. The call is named so you can fix it, or pass `--allow-caller-violations` to
  accept the contract anyway; a contract no value satisfies is still rejected.
- **`rejected (vacuous-branch)`.** A precondition that closes its sites only by making
  their branch unreachable, as `n : {Int | _ <= j}` does for the `else` of
  `if j >= n do v else Array.set(v, j, …) end`. It is not a contract, so it is not
  proposed. The line names the site.
- **`external callers`.** A precondition on a public function with no caller in the project
  is shown but not written: in a library, its real callers are elsewhere. `--apply-public`
  writes it too.
- **No inference for a file.** The file is named, with the compiler's reason: it does not
  typecheck, or the `march` on `PATH` is too old to know `--refine-infer`. Nothing is
  proposed for a program that does not typecheck.

The project is checked as **one unit**, so a caller in another file counts. If the project
does not check as a unit, each file is tried on its own.

**`--apply` cannot leave a half-applied project.** After writing, it re-checks and compares
the result with what it predicted. On any difference it puts every file back and exits
with status 3. That is a bug in the inference, never something to reconcile by hand; please
report it with the file. A second run after a successful `--apply` proposes nothing.

The same inference is available from the compiler and the editor:
- `march --check --refine-infer FILE`, with `--refine-infer-diff` and
  `--refine-infer-apply`;
- `--refine-infer-json` emits JSON (version 1, with byte-range edits);
- `--refine-infer-kinds k1,k4` restricts the kinds (`decreases` names the termination
  metrics);
- `--refine-infer-budget N` caps the probes (default 3000);
- `--refine-report --refine-infer` adds a line showing the ledger as it will be once the
  proposals are applied;
- in the editor, the code actions **"Infer refinements for `f`"** and **"Infer refinements
  in this file"** apply the same bytes.

See [Refinement Types]({{ site.baseurl }}/docs/refinement-types/), section "Module-wide
inference".

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

## Dependency Capability Audit

```sh
forge audit --record                             # record each dependency's capability set (forge.caps.lock)
forge audit                                      # exit 1 if a dependency gained authority
forge audit --inferred                           # infer each set from the code (`march caps`), not `needs`
forge audit --inferred --allow-unanalyzable      # gate on the deps that typecheck; list the rest
forge add <name> ... --accept-caps               # keep a new dep that widens the baseline
forge deps --accept-caps                         # keep a hand-edited upgrade that widens it
```

`forge add`, `forge deps` and `forge outdated` use the baseline too: an add, or
a `forge deps` after a hand edit to `forge.toml`, that brings in new authority
is refused unless `--accept-caps`, and `forge outdated` shows what each
available upgrade would newly ask for. Installing what `forge.lock` already
says is never gated.

`--inferred` needs a toolchain whose `march` supports `caps` (0.3.0 or later)
and stops with the toolchain's path and version if it does not. It caches
each dependency's result under `.forge/audit-cache/`, so only changed
dependencies are re-analyzed. A dependency that does not typecheck fails the
audit unless `--allow-unanalyzable` is given, and it is listed with the
compiler's reason either way. See [Capability Audit](capability-audit.md).

---

## License Audit

```sh
forge licenses             # list each dependency and its declared license
forge licenses --json      # JSON output for tooling
forge licenses --strict    # exit non-zero if any dependency has no license
```

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
forge add check --git https://github.com/march-language/check --tag v0.4.0 --dev

# Test-only dependency
forge add fixtures --path ../fixtures --test

# Overwrite an existing dependency entry
forge add depot --git https://github.com/march-language/depot --tag v1.3.0 --force

# Keep a dependency that asks for capabilities forge.caps.lock does not grant
forge add fs_helpers --path ../fs_helpers --accept-caps
```

With a capability baseline (`forge.caps.lock`, see
[Capability Audit](capability-audit.md)), `forge add` refuses a dependency
that brings in new authority and restores `forge.toml` and `forge.lock`,
unless `--accept-caps` is given.

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

Every `build`, `check`, `run`, `test` and `bench` re-hashes each cached git or registry dependency it is about to use against the `hash` in `forge.lock`, once per command. This is a local re-hash with no network access, and it costs about 0.01 s for a 1.8 MB dependency. If a cached tree does not match (it was edited or corrupted), forge fetches the locked commit or version again, checks the fresh copy against the same hash, swaps it in, and prints one note naming the dependency. If the fresh copy does not match either, the cache was not the cause: `forge.lock` or the upstream source has changed. The command then fails, naming the dependency, the hash in `forge.lock` and the hash of the fresh copy. Run `forge deps` to re-lock it if you expect the upstream change. `forge deps` also replaces a cached git tree that does not match its commit; before, it kept the edited tree and wrote that tree's hash into `forge.lock`. Offline, a mismatch is always an error (see below).

### Offline Builds

`--offline` is a global flag: every command accepts it, in any position before a bare `--` (`forge build --offline`, `forge --offline test`). Setting `FORGE_OFFLINE=1` does the same; either one turns offline mode on, and neither can turn it off once the other has.

```sh
forge deps                 # once, with network access: fills the local cache
forge deps --offline       # "can I build on a plane?": cached / missing per dep
forge build --offline      # build using only what is cached
```

Offline, forge starts no process that talks to the network: no `git clone`, no registry query (it does not even compile the registry client), no toolchain download, no `npm install`. Anything that needs one refuses with a message naming what it would have fetched and which command, run with network access, fills the cache.

- **Dependencies come from `forge.lock` only.** Each git or registry dependency is looked up at `~/.march/cas/deps/<name>/<commit-or-version>`, using the commit or exact version the lockfile recorded. Offline mode never chooses a version: a registry dependency that is not in `forge.lock` is skipped even when some version of it is cached.
- **A missing dependency is a warning, not an error.** The build, check, test or run goes ahead without it; if your code imports it, the compiler's `Unknown module` error follows the warning, which names the dependency and its cache directory.
- **An unusable lockfile is reported once.** A missing `forge.lock`, or a `forge.lock` that is not a lockfile (for example one holding `forge.toml` syntax), gets one error, and only path dependencies are used. If `forge.toml` has changed since `forge deps`, you get one warning that the locked versions may be stale.
- **Cached trees are checked.** Each cached dependency is re-hashed against the `hash` in `forge.lock` before an offline build uses it. A mismatch fails the build, and the error names the dependency, the expected hash and the actual hash. Running the command again without `--offline` re-fetches the dependency.
- **`forge deps --offline`** fetches and rewrites nothing. It prints one line per dependency and exits non-zero if any is missing or fails its hash check.
- **`forge add`** (registry or git) and **`forge outdated`** refuse offline. `forge add --path` still works.

Registry tarballs are cached as well, at `~/.march/cas/tarballs/<sha256>.tar.gz`, keyed by the checksum the registry publishes. A re-install of the same version reuses the cached tarball instead of downloading it again. Offline, a registry dependency whose extracted tree was deleted is re-extracted from the cached tarball. Every read re-hashes the tarball. A corrupt one is reported and discarded, never extracted.

`forge vendor` (committing dependencies in-tree) is not implemented.

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
forge toolchain install v0.6.0
forge toolchain install nightly          # latest nightly
forge toolchain install nightly-20251201

# Switch the active toolchain
forge toolchain use v0.6.0

# Pin this project to a specific version (writes .march-version)
forge toolchain pin v0.6.0

# Show which toolchain resolves for the current directory
forge toolchain which

# Remove an installed toolchain
forge toolchain uninstall v0.2.0

# Install the latest stable and make it active
forge upgrade
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

## forge topology: the topology file

`forge topology check` validates a `topology.toml` (which function or actor serves each protocol role, which pools of nodes serve which roles, hosts per environment) against your sources with `file:line` errors, and runs automatically in `forge build`, `forge run` and `forge deploy hot`. `forge topology export --json` prints the digested topology with the pool connectivity graph; `forge topology gen systemd|ufw|do-firewall|compose` writes deployment files from it, and any `forge-topology-<target>` on `PATH` is a generator plugin. See the [Topology](topology.md) page.

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

## forge observe: what a running node is doing

A compiled program started with `MARCH_OBSERVE_SOCKET=<path>` (or with `MARCH_HOT_RELOAD_SOCKET`, which puts the observe socket at `<path>.observe`) answers read-only questions about itself on that owner-only socket: its actors and mailboxes, supervision tree, names, schedulers, memory, crashes and hot-reload epochs. It never shows message contents or panic text.

```bash
forge observe --socket /tmp/app.observe actors mbox 10   # one request, the JSON reply
forge top --env web --sort msgs_in                      # the busiest actors, redrawn in place
forge diagnose --env web                                # known trouble; exit 0/1/2/3
forge status                                            # every node at a glance
```

From inside a program, the `Recon` and `Diagnose` stdlib modules ask the same questions. [Observing a running node](observe.md) is the operator's guide: every verb and field, the forge commands' flags and exit codes, what each `forge diagnose` finding means and what to do about it, and a worked incident.

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
forge release tag --bump minor   # the same, spelled as the subcommand
```

### Release bundles: `forge release build`

`forge release build [--target T] [--profile release|debug] [--tar]` builds the app and lays out a self-contained directory, `.march/release/<app>-<version>-<target>/`, that you copy to a host and run with nothing but a POSIX shell:

```text
bin/<app>                 launcher (POSIX sh)
lib/<app>                 the binary (the hot-reload baseline when [hot-reload] is set)
lib/<app>.hcr_manifest    from a --compile-so build of the same source (hot-reload only)
lib/<app>.schemas.json    its actor schemas (hot-reload only, when there are actors)
lib/patches/              reserved for the host's patch stack
etc/topology.json         the exported topology (when the project has a topology.toml)
etc/policy, etc/debug_policy, etc/shell_policy   MARCH_DEPLOY_POLICY / MARCH_DEBUG_POLICY / MARCH_SHELL_POLICY
etc/pubkey                the [hot-reload] public key
etc/env                   NAME=VALUE defaults the launcher applies (never overriding the environment)
RELEASE                   name, version, target, profile, cas_hash, hot_reload, compiler, built_at
```

`--target linux/amd64` (or `linux/arm64`) cross-builds like `forge build --target` (needs `zig` and the cross sysroot). The policy files start empty (nothing allowed); a project can ship its own in `release/etc/{policy,debug_policy,shell_policy,env}`, which the build copies in. `etc/env` also carries `MARCH_STOP_GRACE`, the topology's soft drain deadline in seconds.

The launcher, `bin/<app> <verb>`:

| Verb | Does |
|---|---|
| `start [args]` | run the node in the foreground (pidfile in `run/`) |
| `daemon [args]` | start detached, wait until the observe socket answers; output in `log/` |
| `stop` | SIGTERM, then SIGKILL after `MARCH_STOP_GRACE` seconds. A drained stop needs the deploy key: use `forge deploy --drain` |
| `restart` | `stop`, then `daemon` |
| `pid` | the node's pid (exit 1 if not running) |
| `version` | the `RELEASE` file and, if running, the node's code epoch |
| `ping`, `status` | ask the node's observe socket (`PING`; `EPOCHS` and `MEM`) |
| `rpc`, `shell`, `observe`, `diagnose` | `exec forge <verb> --socket ...` when `forge` is on the host, else print what to run from an operator machine |
| `eval` | not available yet (needs a fresh `march` process; says so) |

The node's sockets are `run/<app>.sock` (reload; its shell socket is `.shell`) and `run/<app>.sock.observe`. Override the directories with `MARCH_RUN_DIR` / `MARCH_LOG_DIR` (a Unix socket path must stay under about 100 bytes). `start`, `daemon`, `stop` and `restart` refuse to run as a user other than the owner of the release directory (`MARCH_ALLOW_ANY_USER=1` overrides). The host needs POSIX `sh` and `awk`, plus, for `ping`/`status`/`version`'s epoch and the `daemon` readiness wait, one of `nc -U`, `socat` or `python3`.

`forge topology gen systemd --release-dir /opt/app/current` points each unit's `ExecStart` at `/opt/app/current/bin/<app> start`.

### Publishing

`forge publish` validates the package and optionally checks that the version bump is correct given the API changes:

```sh
forge publish
forge publish --dry-run                          # validate only, don't submit
forge publish --old-source ../my_lib-v1.0        # enforce semver against old API surface
```

When `--old-source` is provided, forge computes the API surface diff and errors if the declared version bump is too small (e.g. a breaking change requires a major bump).

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

## Shell Completions

Generate a completion script for your shell and source it:

```sh
forge completions bash >> ~/.bashrc
forge completions zsh  >> ~/.zshrc
forge completions fish > ~/.config/fish/completions/forge.fish
```

---

## Environment Variables

| Variable | Effect |
|----------|--------|
| `MARCH_LIB_PATH` | Colon-separated paths for multi-file project discovery |
| `MARCH_TRACE_GC` | Set to `1` to log GC events to `trace/gc/gc.jsonl` |
| `MARCH_HISTORY_FILE` | REPL history file path (default: `~/.march_history`) |
| `MARCH_HISTORY_SIZE` | Max REPL history entries (default: 1000) |
| `MARCH_ENV` | `development` / `test` / `production` (read by `Config.env`) |
| `FORGE_OFFLINE` | `1` (or any value but `0`/`false`/`no`/`off`) runs forge in [offline mode](#offline-builds), same as `--offline` |

---

## See also

- [Getting Started](getting-started.md): set up your first project with forge
- [REPL](repl.md): interactive exploration
- [Standard Library](stdlib.md): what you can search with `forge search`
- [Observing a running node](observe.md): the operator's guide behind `forge status`, `diagnose`, `top` and `observe`
- [Hot Code Reload](hot-code-reload.md): the full `forge deploy` story
- [Capability Audit](capability-audit.md): `forge audit` and `forge cap inspect` in depth
