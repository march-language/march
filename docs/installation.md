---
layout: page
title: Installation
nav_order: 2
---

# Installation

March is built from source. The toolchain is OCaml 5.3.0 + dune, managed with opam.

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| opam | 2.x | OCaml package manager |
| OCaml | 5.3.0 | Set up via opam switch |
| dune | 3.7+ | Build system (installed by opam) |
| LLVM / clang | 18+ | Native code compilation |
| git | any | Clone the repository |

### macOS

```sh
brew install opam llvm
opam init --bare -y
```

Homebrew puts clang on your PATH automatically. LLVM 18+ is required; earlier versions may work but are untested.

### Linux (Debian / Ubuntu)

```sh
sudo apt-get install -y opam clang-18 llvm-18-dev libllvm18
opam init --bare -y
```

For other distributions use your package manager to install `opam` and a recent `clang` / `llvm-dev`.

---

## 1. Clone

```sh
git clone https://github.com/march-lang/march.git
cd march
```

---

## 2. Create the opam switch

March uses a dedicated opam switch pinned to OCaml 5.3.0. This keeps its dependencies isolated from other OCaml projects.

```sh
opam switch create march 5.3.0
```

This downloads and compiles OCaml — it takes a few minutes the first time.

---

## 3. Install dependencies

```sh
opam install . --deps-only -y
```

Key packages installed:

| Package | Purpose |
|---------|---------|
| `menhir` | Parser generator |
| `ppx_deriving` | Derivation macros (`show`, `eq`, …) |
| `alcotest` | Test framework |
| `qcheck-core` | Property-based tests |
| `notty` | REPL TUI rendering |

---

## 4. Build

```sh
dune build
```

This compiles everything: the compiler, the stdlib, the C runtime, the `forge` build tool, and the LSP server.

---

## 5. Verify

```sh
forge run examples/list_lib.march
```

Expected output:
```
range 1..10:   [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
length:        10
sum 1..10:     55
product 1..5:  120
max:           10
reversed:      [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
append [1..3] [4..6]: [1, 2, 3, 4, 5, 6]
```

---

## 6. Run tests (optional)

```sh
forge test
```

All tests should pass. The suite covers the parser, typechecker, evaluator, stdlib, and forge.

---

## Installing forge to PATH (optional)

To use `forge` directly without a path prefix, install it after building:

```sh
dune install forge
```

This copies the binary to your opam switch's bin directory, which is already on PATH. After this, forge commands work from anywhere:

```sh
forge run my_program.march
forge new my_project
```

---

## Binary locations after build

```
_build/default/
├── bin/main.exe          # march compiler / interpreter
├── forge/bin/forge.exe   # forge build tool
└── lsp/bin/march_lsp.exe # LSP server (for editor integration)
```

---

## Hello, March

Create `hello.march`:

```elixir
mod Hello do
  fn main() do
    println("Hello, March!")
  end
end
```

Run it:

```sh
forge run hello.march
# Hello, March!
```

---

## Troubleshooting

**`Error: No switch installed`**  
Run `opam switch march` (or `eval $(opam env --switch=march)`) to activate the switch in your current shell.

**`clang: error: unknown target triple 'x86_64-unknown-linux-gnu'`**  
Your LLVM version is too old. Install LLVM 18+.

**`dune build` fails with missing `menhir`**  
Run `opam install . --deps-only -y` again — the switch may not have been active when you first ran it.

**Tests fail on Linux with `libffi` errors**  
```sh
sudo apt-get install libffi-dev
```

---

## Next Steps

- [Getting Started](getting-started.md) — write your first real program
- [Language Tour](tour.md) — a guided introduction to the language
- [Tooling](tooling.md) — forge, LSP, and the debugger
