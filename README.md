# March

March is a statically-typed functional language in the ML/Elixir family. It compiles to native binaries via LLVM.

```march
mod Greet do

fn greet(name : String) : String do
  "Hello, " ++ name ++ "!"
end

fn main() : Unit do
  println(greet("world"))
end

end
```

## Features

**Type system**
- Hindley-Milner inference with bidirectional checking at function boundaries; annotations are optional except where inference fails
- Algebraic data types with pattern matching
- Records with functional update syntax (`{ r with field: value }`)
- Polymorphic functions monomorphized at compile time (no boxing overhead)
- Linear and affine types for ownership, safe mutation, and actor message-passing isolation

**Syntax**
- `fn name(x, y) do ... end`: named functions
- `fn x -> x + 1` / `fn (x, y) -> expr`: lambdas
- `let x = expr`: block-scoped bindings, no `in`
- `match expr do Pat -> body end`: pattern matching
- `if cond do e1 else e2 end`: conditionals
- `x |> f |> g`: pipe operator
- `mod Name do ... end`: modules
- `--` line comments, `{- -}` nested block comments
- Multi-head functions (Elixir-style): consecutive `fn` clauses grouped automatically
- `when` guards on function heads and match branches

**Backend**
- Compiles to LLVM IR, linked to native binaries via `clang`, or to `.wasm` via `--target wasm64-wasi`
- Cross-compiles Linux binaries (`linux/amd64`, `linux/arm64`) from any host via `zig cc`, Go's `GOOS=linux` style
- Perceus reference counting, giving deterministic memory management: no tracing collector and no collection pauses, though freeing a large structure is inline work proportional to its size, at a point you control
- **FBIP (Functional But In-Place)**: when the reference count on a pattern-matched value is 1, destructured nodes are reused in-place rather than freed and reallocated (see below)
- Escape analysis promotes allocations to the stack where possible
- Defunctionalization: closures compiled to structs + dispatch, no indirect call overhead
- Tree-walking interpreter available for fast iteration

**Concurrency**
- Actor model: share-nothing message passing, `spawn`, `send`, `kill`, `is_alive`
- Actor state updated via record spread: `{ state with count: state.count + 1 }`
- Structured concurrency via `Task`: `Task.async`, `Task.await`, `Task.race`, `Task.any`, `Task.all_settled`, `Task.scope`
- Cancellation tokens: `task_cancel_token_new`, `task_cancel`, `task_is_cancelled`, `task_spawn_with_cancel`, `task_cancel_by_id`

## FBIP: Functional But In-Place

One of March's most distinctive performance features is **FBIP (Functional But In-Place)**, derived from the [Perceus reference counting paper](https://www.microsoft.com/en-us/research/publication/perceus-garbage-free-reference-counting-with-reuse/). March code that recursively transforms a data structure can automatically run as fast as (or faster than) equivalent imperative C code that mutates in-place.

### How it works

Every heap-allocated value has a reference count. When the Perceus compiler pass inserts `DecRC` before a match branch body and finds a downstream allocation of the same constructor shape, it replaces the `DecRC + alloc` pair with a single conditional `EReuse` node:

- **RC == 1 (unique owner)**: write the new tag and fields directly into the old allocation. Return the same pointer. Zero allocator calls.
- **RC > 1 (shared)**: decrement the count, allocate fresh. Correct behavior for shared data.

No source-level annotations are needed. The compiler derives this entirely from liveness and shape analysis.

### Example: tree transformation

```march
type Tree = Leaf(Int) | Node(Tree, Tree)

fn inc_leaves(t : Tree) : Tree do
  match t do
    Leaf(n)    -> Leaf(n + 1)         -- rewrites the Leaf in-place when RC=1
    Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))  -- rewrites the Node in-place when RC=1
  end
end
```

With FBIP active, after the initial tree is built, every subsequent pass of `inc_leaves` does **zero heap allocations**: it rewrites the tree's nodes in-place.

### Benchmark: `bench/tree_transform.march`

Depth-20 binary tree (1,048,576 leaves), 100 passes of `inc_leaves`:

| Implementation | Time | Allocations per pass |
|---|---|---|
| March (FBIP off, before the fix) | 11.0 s | 2 × 2^20 = 2M |
| C (`malloc` / `free`) | 8.8 s | 2 × 2^20 = 2M |
| Rust (`Box`) | 9.5 s | 2 × 2^20 = 2M |
| OCaml (GC) | ~3.65 s | 2 × 2^20 = 2M (amortized) |
| **March (FBIP on)** | **1.3 s** | 0 (after pass 1) |

March is **7× faster than C** on this benchmark, not because C is slow, but because `malloc`/`free` carry real overhead (bookkeeping, potential locks, cache pressure). 200M allocator calls across 100 passes add up. March avoids all of them with in-place reuse.

### What patterns benefit

FBIP fires automatically on any function that:

1. Consumes a uniquely-owned value via pattern match (RC == 1)
2. Returns a new value of the same constructor as the matched arm
3. Does not retain the original value alongside the result

This covers `map` over lists, any tree traversal/transformation, and most structural recursion patterns. Functions that alias the original correctly take the RC > 1 fallback path, which allocates fresh.

For the full technical description (including how `shape_matches` works, the TIR `EReuse` node, and the LLVM codegen for the conditional reuse) see the language reference (`specs/lang/index.md`) and the compiler-internals reference (`specs/impl/index.md`).

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
- OCaml 5.3.0 (via opam)
- `clang` (for native compilation)

**1. Install opam** (if needed)

```bash
brew install opam          # macOS
# or: https://opam.ocaml.org/doc/Install.html
opam init
```

**2. Create the OCaml switch**

```bash
opam switch create march 5.3.0
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

## Development workflow

`forge watch` reruns a build, test run, or program on every source change; it
watches `lib/`, `src/`, `test/`, `config/`, and `forge.toml`:

```bash
forge watch          # rebuild on change (default)
forge watch test     # rerun the test suite on change
forge watch run      # rerun the program on change
forge watch --clear --interval 200
```

It never exits on a build/test failure; it reports and keeps watching. Ctrl-C stops it.

`forge bench` compiles and runs every benchmark under `bench/` (each `bench/*.march`
is a standalone program), built at `--opt 2`, reporting wall-clock times:

```bash
forge bench            # run all
forge bench tree       # only benchmarks whose name contains "tree"
forge bench --json     # machine-readable timings for CI tracking
```

## Releasing a package

```bash
forge version                # print the current version
forge version patch          # 1.2.3 -> 1.2.4 (rewrites [package].version)
forge version minor --tag    # bump, commit, and tag vX.Y.Z (needs a clean tree)
forge release                # clean tree -> build -> test -> bump + tag
```

`forge fmt --check` and `forge lint` (which exits non-zero on errors) round out the CI checks.

```bash
forge licenses               # list each dependency and its declared license
forge licenses --strict      # non-zero if any dependency has no license
forge build --frozen         # CI: fail if forge.lock is out of date (don't re-resolve)
```

## AI assistant support

March ships a portable Claude Code skill, `spec-search`, that full-text
searches the language reference and design docs (`specs/lang/`,
`specs/impl/`, `specs/features/`) via a bundled SQLite FTS5 index; no
network access, no dependency on the compiler repo being checked out in
whatever project you're working in:

```bash
git clone https://github.com/march-language/march.git
mkdir -p ~/.claude/skills
cp -R march/.claude/skills/spec-search ~/.claude/skills/spec-search
```

Once installed at `~/.claude/skills/spec-search/`, it's available to Claude
in any project on the machine. See [docs/tooling.md](docs/tooling.md#ai-assistant-search--spec-search-claude-skill)
for query syntax and how to refresh the index after a compiler update.

## Language tour

### Values and bindings

```march
let x = 42
let greeting = "hello"
let flag = true
```

### Functions

```march
fn add(x : Int, y : Int) : Int do
  x + y
end

-- Lambdas
let double = fn x -> x * 2
let add = fn (x, y) -> x + y
```

### Algebraic data types

```march
type Shape = Circle(Float) | Rect(Float, Float) | Point

fn area(s : Shape) : Float do
  match s do
    Circle(r)    -> 3.14159 *. r *. r
    Rect(w, h)   -> w *. h
    Point        -> 0.0
  end
end
```

### Records

```march
type Point = { x : Int, y : Int }

let p = { x: 3, y: 4 }

-- Field access
let px = p.x

-- Functional update (returns a new record)
let q = { p with x: 10 }
```

### Pattern matching

```march
fn describe(n : Int) : String do
  match n do
    0 -> "zero"
    1 -> "one"
    _ -> "many"
  end
end
```

### Higher-order functions

```march
fn double_all(f : Int -> Int, lst : List(Int)) : List(Int) do
  match lst do
    Nil        -> Nil
    Cons(h, t) -> Cons(f(h), double_all(f, t))
  end
end

let doubled = double_all(fn x -> x * 2, my_list)
```

### Option and Result

```march
fn safe_div(a : Int, b : Int) : Option(Int) do
  if b == 0 do None else Some(a / b) end
end

match safe_div(10, 2) do
  None    -> println("error")
  Some(n) -> println(int_to_string(n))
end
```

### Actors

```march
actor Counter do
  state { value : Int }
  init  { value: 0 }

  on Increment(n : Int) do
    { state with value: state.value + n }
  end

  on Report() do
    println(int_to_string(state.value))
    state
  end
end

fn main() : Unit do
  let c = spawn(Counter)
  send(c, Increment(10))
  send(c, Increment(5))
  let _ = send(c, Report())
end
```

### Pipe operator

```march
let result =
  List.range(1, 10)
  |> List.filter(fn x -> x % 2 == 0)
  |> List.map(fn x -> x * x)
  |> List.sum_int
```

## Built-in functions

| Function | Type | Description |
|---|---|---|
| `println(s)` | `String -> Unit` | Print with newline |
| `print(s)` | `String -> Unit` | Print without newline |
| `int_to_string(n)` | `Int -> String` | Format integer |
| `float_to_string(f)` | `Float -> String` | Format float |
| `bool_to_string(b)` | `Bool -> String` | Format boolean |
| `string_length(s)` | `String -> Int` | String length |
| `++` | `String -> String -> String` | String concatenation |

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
stdlib/                  116 March stdlib modules (list, map, http, json, crypto,
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
