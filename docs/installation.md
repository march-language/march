---
layout: page
title: Installation
nav_order: 2
---

# Installation

March is built from source using OCaml 5.3.0, opam, and dune.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| OCaml | 5.3.0 | via opam switch |
| opam | 2.x | OCaml package manager |
| dune | 3.x | Build system (installed via opam) |
| LLVM | 18+ | For native code compilation |
| git | any | To clone the repository |

### macOS

```sh
brew install opam llvm
opam init
```

### Linux (Debian/Ubuntu)

```sh
apt-get install opam llvm-18-dev clang-18
opam init
```

---

## Build Steps

### 1. Clone the repository

```sh
git clone https://github.com/yourusername/march.git
cd march
```

### 2. Create the opam switch

March uses a dedicated opam switch named `march` pinned to OCaml 5.3.0:

```sh
opam switch create march 5.3.0
```

This step takes a few minutes the first time.

### 3. Install dependencies

```sh
opam install . --deps-only
```

Key dependencies installed by opam:
- `menhir` — parser generator
- `ppx_deriving` — derivation macros
- `alcotest` — test framework
- `notty` — REPL TUI
- `odoc` — documentation generator

### 4. Build

```sh
dune build
```

This compiles the compiler, runtime, stdlib, forge build tool, and LSP server.

### 5. Run tests

```sh
dune runtest
```

All tests should pass. The test suite covers the parser, typechecker, evaluator, stdlib, and forge.

---

## Running the Compiler

After building, the compiler binary is at `./_build/default/bin/main.exe`. You can run it directly:

```sh
./_build/default/bin/main.exe your_program.march
```

Or use `dune exec` as a wrapper (no PATH setup needed):

```sh
dune exec march -- your_program.march
```

For convenience, add the compiler to your PATH:

```sh
export PATH="$PWD/_build/default/bin:$PATH"
```

---

## forge Build Tool

The `forge` command is at `./_build/default/forge/bin/forge.exe`:

```sh
dune exec forge -- --help
forge new my_project
forge build
forge test
```

---

## Directory Structure After Build

```
march/
├── _build/                     # dune build output
│   └── default/
│       ├── bin/main.exe        # compiler
│       ├── forge/bin/forge.exe # build tool
│       └── lsp/bin/march_lsp.exe  # LSP server
├── stdlib/                     # March standard library source
├── runtime/                    # C runtime
├── examples/                   # Example programs
└── test/                       # Test suite
```

---

## Verifying Your Build

Create a file `hello.march`:

```elixir
mod Hello do
  fn main() do
    println("Hello, March!")
  end
end
```

Run it:

```sh
dune exec march -- hello.march
```

Expected output:
```
Hello, March!
```

---

## Next Steps

- [Getting Started](getting-started.md) — write your first program
- [Language Tour](tour.md) — a guided introduction to the language
