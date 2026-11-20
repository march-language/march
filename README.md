# March

A statically typed functional language for native, concurrent applications.

March combines ML-style types and pattern matching with isolated actors, explicit
capabilities, and checked communication protocols. It compiles to native binaries through
LLVM and manages memory with Perceus reference counting and automatic in-place reuse.

[Getting Started](https://march-lang.org/docs/getting-started/) ·
[Documentation](https://march-lang.org/) ·
[Try it in the browser](https://march-lang.org/docs/playground/) ·
[Examples](https://march-lang.org/docs/examples/)

## Why March?

- **Explicit authority.** A module declares the capabilities it needs, and `main`'s
  capability parameter is a ceiling on the whole program, dependencies included.
  [Capabilities](https://march-lang.org/docs/capabilities/)
- **Concurrency with guarantees.** Share-nothing actors under supervision trees, with bounded
  mailboxes and backpressure. A protocol is written once and the compiler checks every
  participant, across processes and machines.
  [Actors](https://march-lang.org/docs/actors/) ·
  [Choreography](https://march-lang.org/docs/choreography/)
- **Functional code that reuses memory.** When a value has one owner, the compiler rewrites it
  in place instead of allocating a replacement. `march --why-copies` shows where sharing
  forced a copy, and `@[no_alloc]` makes an allocation a build error.
  [Memory model](https://march-lang.org/docs/memory-model/)
- **Stronger contracts.** Linear types, typestate, and refinement types checked by an SMT
  solver catch resource and value errors before the program runs.
  [Safety by Construction](https://march-lang.org/docs/safety-by-construction/)
- **Native deployment.** `march --compile` produces an executable; `forge` builds, tests,
  cross-compiles, deploys to a running node, and inspects it.
  [Tooling](https://march-lang.org/docs/tooling/)

## An example

An actor, a module that declares what it touches, and a `main` that is granted the console
and nothing else:

```march
mod Chat do
  needs IO.Console

  actor Room do
    state { members : List(String) }
    init  { members: [] }

    on Enter(name : String) do
      { state with members: Cons(name, state.members) }
    end

    on Say(from : String, text : String) do
      state.members |> List.each(fn m -> println("${m} sees ${from}: ${text}"))
      state
    end
  end

  fn main(cap : Cap(IO.Console)) : () do
    let room = spawn(Room)
    send(room, Enter("alice"))
    send(room, Enter("bob"))
    send(room, Say("alice", "hello!"))
    run_until_idle()
  end
end
```

The grant covers the actor's handlers too. Add `file_write("chat.log", text)` to the `Say`
handler and the build fails, naming the path from `main`:

```
`main` is granted `Cap(IO.Console)`, but the program reaches `IO.FileWrite`
(reached from `main`: main → Room → Room_Say). The grant is a ceiling on the WHOLE
program — declaring `needs IO.FileWrite` does not raise it.
```

These checks happen at compile time and are not a sandbox on their own. The
[capability threat model](https://march-lang.org/docs/capability-threat-model/) says what
is guaranteed, what is assumed, and what the opt-in OS sandbox adds.

## In-place reuse

```march
type Tree = Leaf(Int) | Node(Tree, Tree)

fn inc_leaves(t : Tree) : Tree do
  match t do
    Leaf(n)    -> Leaf(n + 1)
    Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
  end
end
```

When the tree has one owner, each node is rewritten in place; when it is shared, the
function allocates as usual. No annotations are involved.

Depth-20 tree (1,048,576 leaves), 100 passes of `inc_leaves`. Median of 10 runs, Apple M3
Max, `--opt 2`, from [`bench/RESULTS.md`](bench/RESULTS.md) (2026-07-24):

| Implementation | Median | Allocations per pass |
|---|---|---|
| **March, reuse on** | **579 ms** | 0 (after pass 1) |
| March, reuse disabled | 3842 ms | 2M |
| Elixir (BEAM) | 2369 ms | 2M |
| OCaml (`ocamlopt`) | 3670 ms | 2M |
| Rust (`rustc -O`, `Box`) | 4902 ms | 2M |

Read this as in-place reuse against allocation, not as March against those languages in
general. The Rust, OCaml and Elixir programs (`bench/rust/`, `bench/ocaml/`, `bench/elixir/`)
build a fresh tree every pass; a Rust version that mutates through `&mut`, or a C version
that reuses nodes, is not benchmarked. On the other workloads in the same table March is
behind: fib(40), binary-trees(15) and list-ops(1M) are all faster in Rust or OCaml.

## Quick start

```bash
# Interpret a file
march file.march

# Compile to a native binary
march --compile file.march        # produces ./file
march --compile -o hello file.march

# Cross-compile a Linux binary from any host (requires zig — see Cross-compilation below)
march --compile --target linux/amd64 file.march -o app   # x86-64 Linux ELF
march --compile --target linux/arm64 file.march -o app   # aarch64 Linux ELF

# Compile to WebAssembly (requires wasi-sdk + wasmtime — see below)
march --compile --target wasm64-wasi file.march   # produces file.wasm
wasmtime --wasm memory64 file.wasm

# Emit LLVM IR
march --emit-llvm file.march      # produces file.ll
march --emit-llvm --target wasm64-wasi file.march

# Interactive REPL
march
```

## Install a prebuilt binary

Prebuilt binaries are published as [GitHub releases](https://github.com/march-language/march/releases) for `darwin-arm64`, `linux-x86_64`, and `linux-aarch64`. Each archive bundles the `march` compiler, the `forge` build tool, the standard library, and the C runtime sources.

The binaries are self-contained (the macOS build statically links `blake3`/`zstd`/`brotli` and the Linux builds are statically linked), so **running** March (interpreting programs) needs no extra packages.

> **To use `march --compile`** you also need a C toolchain installed: `clang` + LLVM. On macOS install the Xcode Command Line Tools (`xcode-select --install`); on Linux install e.g. `clang llvm`. The compiler shells out to `clang` to build the bundled runtime.

### One-line installer

```bash
curl -fsSL https://raw.githubusercontent.com/march-language/march/main/install.sh | sh
```

This downloads the latest release into `~/.march`, verifies its checksum, and installs `march` and `forge` into `~/.march/bin` (add that to your `PATH` as the script prints). Set `MARCH_VERSION=nightly` for the latest nightly, or `MARCH_VERSION=<tag>` to pin a specific release.

### Managing toolchains with forge

Once `forge` is installed, it manages March versions rustup-style:

```bash
forge toolchain install            # latest stable (falls back to newest nightly)
forge toolchain install nightly    # latest nightly
forge toolchain use <version>      # switch the active toolchain
forge toolchain list               # show installed versions
forge toolchain uninstall <version>
```

Both the installer and `forge toolchain` share the `~/.march/versions/<tag>` layout and switch the active toolchain via the `~/.march/current` symlink.

> **Note:** `forge toolchain`, the bundled runtime (native compile), and static linking ship in releases built from the current sources. Nightlies published earlier predate them; installing one still works for interpreting, but those features require a newer release. The manual download below works against any release.

### Manual download

```bash
PLATFORM=darwin-arm64        # or: linux-x86_64, linux-aarch64
api="https://api.github.com/repos/march-language/march/releases"

# Download the latest nightly tarball + checksums
url=$(curl -fsSL "$api"  | grep browser_download_url | grep "${PLATFORM}.tar.gz" | head -1 | cut -d'"' -f4)
sums=$(curl -fsSL "$api" | grep browser_download_url | grep "checksums.txt"      | head -1 | cut -d'"' -f4)
curl -fsSLO "$url"
curl -fsSLO "$sums"

# Verify the checksum (sed strips a legacy "sha256:" prefix if present;
# use shasum on macOS, sha256sum on Linux)
sed 's/^sha256://' march-*-checksums.txt | shasum -a 256 -c --ignore-missing

# Extract and add to PATH
tar xzf march-*-"${PLATFORM}.tar.gz"
toolchain="$PWD/$(ls -d march-*-${PLATFORM}/)"
export PATH="${toolchain}bin:$PATH"
```

Add the final `export PATH=...` line (with the real path) to your `~/.zshrc` or `~/.bashrc` to make it permanent. Then:

```bash
march hello.march                            # interpret a program
march --compile -o hello hello.march         # compile to a native binary
./hello
```

## Installing from source

**Prerequisites**
- OCaml 5.5.1 (via opam)
- `clang` (for native compilation)

**1. Install opam** (if needed)

```bash
brew install opam          # macOS
# or: https://opam.ocaml.org/doc/Install.html
opam init
```

**2. Create the OCaml switch**

```bash
opam switch create march 5.5.1
eval $(opam env --switch=march)
```

**3. Clone and build**

```bash
git clone https://github.com/march-language/march.git
cd march
opam install . --deps-only
dune build
```

**4. Run the compiler**

```bash
dune exec march -- examples/list_lib.march
dune exec march -- --compile examples/list_lib.march
./examples/list_lib
```

To install `march` into your PATH:

```bash
dune install
```

## WebAssembly target

March can compile pure functional programs to `.wasm` via the `--target wasm64-wasi` flag. Actors, networking, and file I/O are not yet available in WASM builds (Tier 1, pure compute only).

**Install prerequisites**

```bash
brew install wasi-sdk wasmtime
# or download from:
#   https://github.com/WebAssembly/wasi-sdk/releases
#   https://wasmtime.dev
```

**Compile and run**

```bash
march --compile --target wasm64-wasi file.march   # → file.wasm
wasmtime --wasm memory64 file.wasm
```

Set `WASI_SDK_PATH` if wasi-sdk is installed somewhere other than `/opt/wasi-sdk`:

```bash
export WASI_SDK_PATH=/path/to/wasi-sdk
march --compile --target wasm64-wasi file.march
```

Available targets: `native` (default), `linux/amd64`, `linux/arm64`, `wasm64-wasi`, `wasm32-wasi`, `wasm32-unknown-unknown`, `js`.

## Cross-compilation to Linux

Build a Linux binary from any host, including macOS, the way Go's `GOOS=linux go build` does, using [`zig cc`](https://ziglang.org) as the C cross-compiler:

```bash
brew install zig          # macOS; or download from https://ziglang.org/download/

march --compile --target linux/amd64 file.march -o app   # x86-64 Linux ELF
march --compile --target linux/arm64 file.march -o app   # aarch64 Linux ELF
forge build --target linux/amd64                          # via forge (per-target output dir)
```

You get a dynamically-linked **glibc** binary (min glibc 2.31) that runs on mainstream distributions and in glibc containers (`debian:*-slim`, `ubuntu:*`, distroless-cc). Cross builds currently cover **compute and CLI workloads**; TLS/HTTPS, compression, hot code reload, and Rust FFI are not yet included. See the [cross-compilation guide](docs/tooling.md#cross-compiling-to-linux) for details.

## Running the tests

```bash
dune runtest
```

## More

The language reference, guides and tool documentation live at
[march-lang.org](https://march-lang.org/):

- [Language tour](https://march-lang.org/docs/tour/) and the
  [type system](https://march-lang.org/docs/types/)
- [Session types](https://march-lang.org/docs/session-types/),
  [clustering](https://march-lang.org/docs/clustering/) and
  [hot code reload](https://march-lang.org/docs/hot-code-reload/)
- [`forge` reference](https://march-lang.org/docs/tooling/): watch mode, benchmarks,
  releases, dependency and license audits, cross-compilation, the JavaScript backend, and
  the `spec-search` skill for AI assistants
- [LSP and editors](https://march-lang.org/docs/lsp/)
- [Supported platforms](https://march-lang.org/docs/platforms/), including the experimental
  WebAssembly targets

## Project layout

```
bin/main.ml              compiler entry point (parse → desugar → typecheck → eval/compile)
lib/
  ast/ast.ml             AST types (span, expr, pattern, decl, ...)
  lexer/lexer.mll        ocamllex lexer
  parser/parser.mly      menhir parser
  desugar/desugar.ml     pipe desugar, multi-head fn grouping
  typecheck/typecheck.ml bidirectional HM type inference
  eval/eval.ml           tree-walking interpreter
  tir/                   typed IR: lower, mono, defun, perceus (+ borrow, fusion),
                         llvm_emit, and companion passes
  jit/                   REPL JIT compiler
  errors/errors.ml       diagnostic type (Error/Warning/Hint + span)
  search/search.ml       Hoogle-style type/name search engine
  refine/                refinement-types Z3 bridge
stdlib/                  140 March stdlib modules (list, map, http, json, crypto,
                         distributed-OTP actors, DataFrame, ...)
runtime/                 C runtime (alloc, RC, scheduler, HTTP, TLS, WASM)
forge/                   build tool (new, build, run, test, deps, publish, ...)
lsp/                     LSP server (diagnostics, hover, goto-def, completions, code actions)
test/                    alcotest suites over the compiler, stdlib, and codegen
examples/
  list_lib.march         map, filter, fold, reverse, find
  actors.march           actor spawning, messaging, kill/restart
specs/                   language and compiler design documents
```

## License

MIT
