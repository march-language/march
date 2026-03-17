# March — Progress Summary

## What Is March

A statically-typed functional programming language. The compiler is implemented in OCaml 5.3.0. The name is "March."

## Design Decisions Made

### Type System
- **Hindley-Milmer inference with bidirectional type checking** at function boundaries — balances inference convenience with good error localization
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
- **Concurrency**: `Pid(a)`, `Cap(a)`, `Future(a)`, `Stream(a)`, `Task(a)` (structured concurrency), `Node`
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
- **Content-addressed code** — whole-definition hashing (SHA-256), names are aliases to hashes
- **Query-based/demand-driven compiler architecture** (not a pipeline) — incremental recompilation falls out naturally
- **Compilation target**: LLVM IR

### Compiler Pass Order
1. Parse (with hole injection on error)
2. Desugar multi-head functions → single function with match (Erlang-style)
3. Type check (bidirectional, provenance-tracked, linearity)
4. Session type verification (on actor/protocol code)
5. Strip provenance metadata
6. Monomorphize (resolve representation polymorphism)
7. Defunctionalize (closures → tagged unions)
8. Code generation

## Implementation Language
- **OCaml 5.3.0** via opam switch named `march`
- Dependencies: dune, menhir, ppx_deriving, alcotest, odoc
- `opam` and `dune` are available directly in PATH

## Project Structure

```
march/
├── CLAUDE.md                # Build instructions and project map
├── specs/design.md          # Full language design spec
├── specs/epochs-design.md
├── specs/gc_design.md
├── progress.md              # This file
├── dune-project
├── .gitignore
├── .ocamlformat
├── bin/
│   ├── dune
│   └── main.ml              # parse → desugar → typecheck → eval pipeline
├── lib/
│   ├── ast/ast.ml           # Full AST: spans, exprs, patterns, decls, actors
│   ├── lexer/lexer.mll      # ocamllex: atoms, pipes, do/end, when, etc.
│   ├── parser/parser.mly    # menhir: full expression grammar, fn head grouping
│   ├── desugar/desugar.ml   # pipe desugar, multi-head fn → single EMatch clause
│   ├── typecheck/typecheck.ml  # Bidirectional HM, constructor registry, error recovery
│   ├── eval/eval.ml         # Tree-walking interpreter, base_env builtins
│   ├── effects/effects.ml   # Placeholder
│   ├── codegen/codegen.ml   # Placeholder
│   └── errors/errors.ml     # Diagnostic type (Error/Warning/Hint + span)
└── test/
    ├── dune
    └── test_march.ml        # 40 passing tests
```

## Current State

- **Builds clean**
- **40 tests passing**: lexer (12), AST (1), parser (5), module (2), keywords (1), desugar (3), typecheck (8), eval (8)
- **Full pipeline working**: `march file.march` parses → desugars → typechecks → runs `main()` if present
- Bidirectional HM type checker with constructor registry (`DType` → `ctor_info`), builtin `Some/None/Ok/Err`
- Tree-walking interpreter: `value` type, pattern matching, `base_env` builtins, two-pass `eval_module_env` for mutual recursion

## Next Steps

### Blocking real programs (do first)
1. **Unary minus / negative literals** — `-5` currently parses as `0 - 5` binary subtraction at best; needs a `MINUS expr` unary rule in the parser or negation sugar
2. **Top-level let bindings evaluate at module init** — currently `DLet` in `eval_decl` works, but hasn't been stress-tested with non-trivial expressions
3. **Recursive closure bug** — a `VClosure` captures `env` at creation time; lambdas defined inside top-level fns won't see peer top-level fns defined after them. Fix: closures should look up names lazily via `env_ref`.
4. **List literal syntax** — `[1, 2, 3]` desugars to `Cons(1, Cons(2, Cons(3, Nil)))`. Currently no list syntax; users must write constructors by hand.

### REPL (next major feature)
- `march` with no file argument drops into a read-eval-print loop
- Reads one declaration or expression at a time
- Maintains a running `env` across lines
- Pretty-print values (needs a proper `value_to_string` for structured values)

### IR / codegen (after REPL)
- Decision needed: emit C, LLVM IR, or a custom bytecode first?
- See briefing below (to be written once REPL is done)

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
