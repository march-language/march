# March — Progress Summary

## What Is March

A statically-typed functional programming language. The compiler is implemented in OCaml 5.3.0. The name is "March."

## Design Decisions Made

### Type System
- **Hindley-Milner inference with bidirectional type checking** at function boundaries — balances inference convenience with good error localization
- **Type annotations optional** everywhere except where inference fails (recursive functions, ambiguous overloads)
- **Linear and affine types** for ownership, safe mutation, actor message-passing isolation, and FFI safety
- **Provenance-tracking types** — every type constraint carries a *reason* chain (not just a span), so errors explain *why* a type was expected
- **Error recovery via typed hole injection** — errors become typed holes; the compiler continues and reports multiple diagnostics. Same mechanism as user-written `?` holes.
- **Unboxed types / representation polymorphism** — compiler chooses boxed vs unboxed based on usage, after monomorphization
- **Type-level naturals** — `Nat` in type parameters with `+`, `*`, equality. Enables `Vector(n, a)`, `Matrix(m, n, a)`, `NDArray(shape, a)` with compile-time dimension checking. Not full dependent types.
- **No algebraic effects** (removed — concurrency is actors + message passing)
- **ADTs use capitalized constructors** (`Ok`, `Err`, `Some`, `None`) — atoms (`:name`) are lightweight runtime tags for messaging, not type constructors
- **Pony-style capabilities**: No. Linear/affine is the ceiling.

### Module System
- **`mod Name do ... end`** — namespaces; definitions private by default, `pub` to export
- **`sig Name do ... end`** — explicit interface declarations; get their own hash separate from implementation hashes. Downstream code depends on the sig hash — internal refactors don't invalidate downstream caches.
- **`interface Name(a) do ... end`** — typeclasses with default implementations and associated types; covers ML functor use cases without functor complexity
- **`impl Interface(Type) do ... end`** — implement an interface for a type, with conditional impls via `when` constraints
- **Content-addressed versioning** — names are aliases to hashes; the build system auto-generates a lockfile of resolved hashes. No version numbers. No dependency conflicts (different hashes coexist).

### Built-in Types
- **Primitives**: `Int` (64-bit), `Float` (64-bit), `Byte` (8-bit), `Bool`, `String` (UTF-8), `Char` (Unicode scalar)
- **Stdlib numeric**: `BigInt`, `Decimal` (exact, for money/finance), `Ratio` — numeric abstraction via `Num`/`Fractional` interfaces
- **Strings**: `String`, `Char`, `Rope` (stdlib), `Regex` (stdlib). String interpolation via `${}` desugared to `Interpolatable` interface.
- **Collections**: `List(a)`, `Array(a)` (fixed-size contiguous), `Map(k, v)`, `Set(a)`, `Option(a)`, `Result(a, e)`
- **Sized arrays**: `Vector(n, a)`, `Matrix(m, n, a)`, `NDArray(shape, a)` — dimension-checked at compile time via type-level naturals
- **Concurrency**: `Pid(a)` (location-transparent), `Cap(a)`, `Future(a)`, `Stream(a)`, `Task(a)` (structured concurrency), `Node`
- **Constraints**: `Sendable(a)` — compiler-derived, marks types safe to cross node/thread boundaries
- **FFI**: `linear Ptr(a)`, per-library `Cap(LibName)`

### Concurrency
- **Actors** — share-nothing message passing with private state, isolation guaranteed by linear types
- **Actor state updates** use record spread: `{ state with field = new_value }`
- **Binary session types** for v1 — typed two-party protocols verified at compile time (catches deadlocks, protocol violations, missing cases). Multi-party deferred post-v1.
- **Capability-secure messaging** — actors can only message actors they hold an unforgeable capability reference to; linear capabilities enable ownership transfer
- **Content-addressed message schemas** — messages reference their schema by hash for safe distributed communication
- **Location-transparent `Pid`** (Erlang model) — you don't know or care which node an actor lives on
- **`Future(a)`** for async actor results, **`Stream(a)`** for ongoing sequences, **`Task(a)`** for structured parallel compute

### Syntax (ML/Elixir Hybrid)
- `fn name(x, y) do ... end` — named functions with parenthesized args
- `fn x -> x + 1` / `fn(x, y) -> body` — lambdas (require `fn` keyword to avoid parser ambiguity)
- `mod Name do ... end` — modules; `sig Name do ... end` — interfaces
- `do ... end` blocks everywhere, not indentation-sensitive
- `x |> f |> g` — pipe operator
- `let x = expr` — block-scoped, no `in` keyword
- `match expr with | Pat -> body end` — pattern matching
- `?name` / `?` — typed holes
- `:ok`, `:error` — atoms as typed tags belonging to declared atom sets
- **Function head matching** — consecutive `fn` clauses with the same name are grouped (Elixir-style multi-head)
- `when` guards on function heads and match branches
- `--` line comments, `{- -}` nested block comments

### Compiler Backend
- **Whole-program monomorphization** — all polymorphic functions specialized to concrete types (like Rust/MLton)
- **Defunctionalization** — closures become tagged unions + dispatch (no closure allocation, no indirect calls)
- **Content-addressed code** — whole-definition hashing (SHA-256), names are aliases to hashes. Enables: reproducible builds, incremental compilation via hash caching, no dependency conflicts, safe distributed actor migration, semantic code search
- **Query-based/demand-driven compiler architecture** (not a pipeline) — incremental recompilation falls out naturally
- **Compilation target**: LLVM

### Compiler Pass Order
1. Parse (with hole injection on error)
2. Desugar multi-head functions → single function with match (Erlang-style)
3. Type check (bidirectional, provenance-tracked, linearity)
4. Session type verification (on actor/protocol code)
5. Strip provenance metadata
6. Monomorphize (resolve representation polymorphism)
7. Defunctionalize (closures → tagged unions)
8. Code generation

### Tooling / LLM Integration
- LSP with type-at-cursor, go-to-definition via content-addressed lookup, type-directed completion
- Typed holes as structured prompts for LLMs (compiler provides expected type + available bindings)
- Canonical formatter (one true format)
- MCP server for direct LLM-compiler integration
- Content-addressed semantic search by type signature
- Tree-sitter grammar planned

## Implementation Language
- **OCaml 5.3.0** via opam switch named `march`
- Dependencies: dune, menhir, ppx_deriving, alcotest, odoc

## Project Structure

```
march/
├── specs/design.md          # Full language design spec
├── progress.md              # This file
├── dune-project             # Dune build config (menhir enabled)
├── .gitignore
├── .ocamlformat
├── bin/
│   ├── dune
│   └── main.ml              # Compiler entry point (stub)
├── lib/
│   ├── ast/
│   │   ├── dune
│   │   └── ast.ml           # Full AST with spans, atoms, linear types,
│   │                        # multi-head fn_def, actors, protocols
│   ├── lexer/
│   │   ├── dune
│   │   └── lexer.mll        # ocamllex: atoms, pipes, do/end, when, etc.
│   ├── parser/
│   │   ├── dune
│   │   └── parser.mly       # menhir: full expression grammar, fn head
│   │                        # grouping, guards, operators, modules
│   ├── typecheck/
│   │   ├── dune
│   │   └── typecheck.ml     # Type checker stub (HM + bidirectional)
│   ├── effects/
│   │   ├── dune
│   │   └── effects.ml       # Capability system stub (replaced effects)
│   ├── codegen/
│   │   ├── dune
│   │   └── codegen.ml       # Code generation stub
│   └── errors/
│       ├── dune
│       └── errors.ml        # Diagnostic system (severity, spans, labels)
└── test/
    ├── dune
    └── test_march.ml         # 21 passing tests (lexer, parser, module, AST)
```

## Current State

- **Builds clean** (menhir warnings for unused tokens that are reserved for future features, 3 shift/reduce conflicts from lambda/expr overlap — harmless)
- **21 tests passing**: lexer (12), AST (1), parser (5), module parsing (2), keywords (1)
- **Git initialized** but no commits yet
- The lexer and parser handle the full surface syntax including atoms, pipes, fn head matching, guards, type annotations, typed holes, operators, and do/end blocks
- Type checker, capability system, and codegen are stubs

## What to Do Next

1. **Commit the initial project** — everything is staged
2. **Implement the type checker** — HM unification with provenance, bidirectional checking, linearity enforcement, type-level naturals, error recovery via typed holes, exhaustiveness checking. Design is fully specified (see conversation history for Sections 1–5).
3. **Build a simple evaluator/interpreter** — useful for testing before codegen exists
4. **Update AST** to include `ERecordUpdate`, `EHole`, and type-level nat nodes
5. **Update parser** for `{ state with ... }` record update syntax and `${}` string interpolation

## Resolved Open Questions

- **Compilation target**: LLVM
- **MPST scope**: Binary session types for v1, multi-party deferred
- **Stdlib scope**: "Some batteries" — collections, strings, IO, Result/Option, Decimal, basic math, actors/messaging
- **GC strategy**: Stratified model — see `specs/gc_design.md`
- **Orphan instances**: Forbidden
- **Pony-style capabilities**: No. Linear/affine is the ceiling.
- **Module system**: Namespaces + interfaces with associated types. No ML functors.
- **Sig hashing**: Sigs have own hash, separate from impl hashes.
- **FFI**: Per-library caps, `unsafe` blocks, explicit `CRepr` interface
- **Actor state updates**: `{ state with field = new_value }` record spread
- **Result/Option types**: Capitalized constructors (`Ok`/`Err`/`Some`/`None`), atoms stay as runtime tags
- **Location transparency**: `Pid(a)` is location-transparent (Erlang model)
- **Type-level naturals**: In v1. `Nat` params with `+`, `*`, equality. Not full dependent types.

## Key Design Tensions to Remember

- **Defunctionalization + representation polymorphism** requires monomorphization first — forces a specific pass order and means no separate compilation of polymorphic code. Content-addressed caching mitigates compile time.
- **Unboxed types + linearity** — linearity checking must happen before representation decisions (on typed IR where all values are abstract).
- **Provenance tracking + defunctionalization** — strip provenance after type checking, before backend passes, to avoid metadata bloat.
- **Type-level nat solver complexity** — must keep it decidable. Only `Nat` in type-level positions, only `+`, `*`, equality. No general term dependency.

## Setup Instructions

```bash
# The opam switch is already created
eval $(opam env --switch=march)

cd ~/code/march
dune build      # builds everything
dune runtest    # runs 21 tests
dune exec march # prints "march 0.1.0 — not yet implemented"
```
