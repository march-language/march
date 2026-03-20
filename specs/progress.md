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
- `fn x -> x + 1` / `fn (x, y) -> body` — lambdas; multi-param requires parens
- `mod Name do ... end` — modules; `sig Name do ... end` — interfaces
- `do ... end` — inline block expression (also valid in match arms)
- `x |> f |> g` — pipe operator
- `let x = expr` — block-scoped, no `in` keyword; subsequent exprs in the block see the binding
- `match expr with | Pat -> body end` — pattern matching; arm bodies are `block_body` (multi-expr ok)
- `if cond then e1 else e2` — conditional expression
- `?name` / `?` — typed holes
- `:ok`, `:error` — atoms as typed tags belonging to declared atom sets
- **Function head matching** — consecutive `fn` clauses with the same name are grouped (Elixir-style multi-head)
- `when` guards on function heads and match branches
- `--` line comments, `{- -}` nested block comments
- Type variants: `type Foo = A | B(Int)` — no leading `|`

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
- `opam` and `dune` are available directly in PATH (source `~/.zshrc` first if needed)

## Project Structure

```
march/
├── CLAUDE.md                # Build instructions, syntax notes, project map
├── specs/design.md          # Full language design spec
├── specs/gc_design.md       # GC strategy (Perceus RC + arenas + FBIP)
├── specs/tir.md             # Typed IR design (ANF, passes, LLVM)
├── specs/defun.md           # Defunctionalization design
├── specs/perceus.md         # Perceus RC analysis design
├── specs/progress.md        # This file
├── examples/list_lib.march  # End-to-end working example
├── examples/actors.march    # Actor system example
├── dune-project
├── .gitignore
├── .ocamlformat
├── bin/
│   ├── dune
│   └── main.ml              # parse → desugar → typecheck → eval + --compile + REPL JIT bootstrap
├── lib/
│   ├── ast/ast.ml           # Full AST: spans, exprs, patterns, decls, actors
│   ├── lexer/lexer.mll      # ocamllex: atoms, pipes, do/end, when, etc.
│   ├── parser/parser.mly    # menhir: full expression grammar, fn head grouping
│   ├── desugar/desugar.ml   # pipe desugar, multi-head fn → single EMatch clause
│   ├── typecheck/typecheck.ml  # Bidirectional HM, constructor registry, error recovery
│   ├── eval/eval.ml         # Tree-walking interpreter, base_env builtins
│   ├── effects/effects.ml   # Placeholder
│   ├── codegen/codegen.ml   # Placeholder
│   ├── errors/errors.ml     # Diagnostic type (Error/Warning/Hint + span)
│   ├── jit/
│   │   ├── jit_stubs.c      # C stubs for dlopen/dlsym/dlclose + call stubs
│   │   ├── jit.ml / jit.mli # OCaml externals wrapping C stubs
│   │   ├── repl_jit.ml/mli  # Compile-and-dlopen REPL engine
│   │   └── dune
│   └── tir/
│       ├── tir.ml           # ANF IR type definitions
│       ├── lower.ml         # AST → TIR (ANF conversion, pattern flattening)
│       ├── mono.ml          # Monomorphization pass
│       ├── defun.ml         # Defunctionalization pass
│       ├── pp.ml            # Pretty-printer
│       ├── perceus.ml       # Perceus RC analysis ✓
│       ├── escape.ml        # Escape analysis ✓
│       └── llvm_emit.ml     # TIR → LLVM IR + REPL emission + HTTP extern decls
├── runtime/
│   ├── march_runtime.c/h    # Core runtime: alloc, RC, strings, actors, value_to_string
│   ├── march_http.c/h       # HTTP/WS runtime: TCP, HTTP parse/serialize, server, WebSocket
│   ├── sha1.c               # SHA-1 for WebSocket handshake
│   └── base64.c             # Base64 for WebSocket handshake
└── test/
    ├── dune
    ├── test_march.ml         # 132 passing tests
    └── test_jit.ml           # JIT dlopen round-trip test
```

## Current State (as of 2026-03-20)

- **Builds clean**
- **132+ tests passing**: lexer (12), AST (1), parser (5), module (2), keywords (1), desugar (3), typecheck (8), eval (12), parser gaps (6), constraints (5), tir (83), list builtins (6), declarations (14), string interp (2), type_map (2), convert_ty (2), perceus (6), jit (1)
- **Full pipeline working**: `dune exec march -- file.march` parses → desugars → typechecks → runs `main()` if present
- **`--dump-tir` flag**: prints TIR after full pipeline (Lower → Mono → Defun → Perceus → Escape); shows `stack_alloc` for promoted allocations
- **`--emit-llvm` flag**: emits textual LLVM IR to `<basename>.ll`; links with `runtime/march_runtime.c` via `clang` to produce native binaries
- **Compiled REPL**: `dune exec march` with no args launches a compile-and-dlopen REPL — each expression goes through the full TIR pipeline → LLVM IR → `clang -shared` → `.so` → `dlopen` → `dlsym` → call. Bindings persist as LLVM globals with `RTLD_GLOBAL`. Falls back to interpreter if JIT unavailable. `:quit`/`:env` commands; incremental env
- **Bidirectional HM type checker**: constructor registry, builtin `Some/None/Ok/Err`, named record type expansion, `Unit`/`Bool`/etc. annotation normalization, builtins (`print`, `println`, `int_to_string`, `bool_to_string`, etc.) in scope; actor declarations register message ctors and bind `state` in handler envs
- **Tree-walking interpreter**: `value` type (incl. `VPid`), pattern matching, `base_env` builtins, two-pass `eval_module_env` for mutual recursion; full synchronous actor runtime with `kill`/`is_alive`/drop semantics
- **TIR pipeline** (`lib/tir/`):
  - `lower.ml` — AST → ANF TIR, CPS let-insertion, nested pattern flattening, type_map threading
  - `mono.ml` — worklist monomorphization, name mangling (`identity$Int`), TVar elimination
  - `defun.ml` — defunctionalization: lambda lifting, `$Clo_` struct generation, `ECallPtr` rewriting
  - `perceus.ml` — Perceus RC analysis: backwards liveness, `EIncRC`/`EDecRC`/`EFree` insertion, Inc/Dec cancel-pair elision, FBIP `EReuse` detection
  - `escape.ml` — Escape analysis: 3-phase intra-procedural stack promotion; `EAlloc` → `EStackAlloc` for non-escaping allocations; dead RC ops on stack vars removed
  - `llvm_emit.ml` — TIR → textual LLVM IR; alloca+store+load for all let-bindings; ECase as switch+blocks+merge; arithmetic/cmp builtins to native ops; EAlloc→`@march_alloc`; EStackAlloc→`alloca`; EReuse→in-place write; March `main` → `@march_main` with C `@main` wrapper; REPL emission helpers (`emit_repl_expr`, `emit_repl_decl`, `emit_repl_fn`); HTTP/WS extern declarations
  - `pp.ml` — pretty-printer for all TIR types and expressions (incl. `stack_alloc`, `reuse`)
- **JIT / compile-and-dlopen** (`lib/jit/`):
  - `jit_stubs.c` — OCaml C stubs for POSIX `dlopen`/`dlsym`/`dlclose` + function pointer call stubs (void→ptr, void→void, void→i64, void→double, ptr→ptr)
  - `jit.ml` / `jit.mli` — OCaml externals wrapping the C stubs
  - `repl_jit.ml` / `repl_jit.mli` — Compiled REPL engine: TIR pipeline → LLVM IR → `clang -shared -fPIC` → `.so` → `dlopen` → call; tracks globals across fragments, deduplicates already-compiled functions, handles fn decls / let bindings / expressions
- **HTTP/WS C runtime** (`runtime/`):
  - `march_http.c` / `march_http.h` — TCP listen/accept/recv/send/close; HTTP request parsing and response serialization; thread-per-connection server accept loop; WebSocket handshake, frame recv/send, and select (with actor pipe support)
  - `sha1.c` — Minimal RFC 3174 SHA-1 for WebSocket handshake
  - `base64.c` — Minimal Base64 encoding for WebSocket handshake
- **Pre-compiled runtime .so** — `ensure_runtime_so()` in `bin/main.ml` compiles `march_runtime.c` + `march_http.c` + `sha1.c` + `base64.c` to `~/.cache/march/libmarch_runtime.so`, cached and rebuilt only when sources change
- **Two working examples**:
  - `examples/list_lib.march` — map, filter, fold, reverse, find, range (polymorphic list library)
  - `examples/actors.march` — Counter + Logger actors, normal messaging, kill, drop semantics, restart
- **Actor system**: `spawn(ActorName)` / `send(pid, Msg(args))` → `Option(Unit)`, `kill(pid)`, `is_alive(pid)`, `{ state with field = ... }` record spread, synchronous inline dispatch
- **Syntax additions**: `%` modulo, multi-statement match arm bodies, zero-arg constructor calls `Con()`, `state` as contextual keyword in expressions

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

## Next Steps

### TIR Pipeline (continuing)
1. ~~**Perceus RC Analysis**~~ ✓ — `lib/tir/perceus.ml` complete. Spec at `specs/perceus.md`.
2. ~~**Escape Analysis**~~ ✓ — `lib/tir/escape.ml` complete. Spec at `specs/escape.md`.
3. ~~**LLVM IR emission**~~ ✓ — `lib/tir/llvm_emit.ml` + `runtime/march_runtime.{c,h}`. `march --emit-llvm file.march` produces `.ll`; link with `clang runtime/march_runtime.c file.ll -o bin`. Verified: `escape_test.march` compiles to native binary printing `7`.

### Next milestones
4. **Field-index map for records** — `EField`/`EUpdate` need a field→offset table (from type checker) to emit correct GEP offsets beyond field 0.
5. ~~**`llc` / `clang` invocation from compiler**~~ ✓ — `march --compile` calls clang automatically; `ensure_runtime_so()` pre-compiles runtime to cached `.so`.
6. **More test programs** — compile list operations, recursive functions, actors to LLVM.
7. **HTTP server stdlib** — March-level HTTP server types, routing, and stdlib modules using the compiled HTTP/WS C runtime.

### Frontend / Ergonomics
4. **More tests** — actor spawning/send/kill, record operations, `Option`/`Result` pattern matching
5. **Typechecker: actor handler return type checking** — handlers should be verified to return the state record type
6. **String interpolation** — `${}` syntax, desugars to `Interpolatable` interface calls
7. **Error recovery in REPL** — currently a type error halts the REPL session

## Stdlib: File System (added 2026-03-20)
- [x] Path module — pure path manipulation (join, basename, dirname, extension, normalize)
- [x] Seq module — lazy church-encoded fold sequences (map, filter, take, drop, fold_while, etc.)
- [x] File module — Result-based I/O (read, write, append, delete, copy, rename, with_lines, with_chunks)
- [x] Dir module — directory operations (list, mkdir, mkdir_p, rmdir, rm_rf)
- [x] FileError ADT — NotFound, Permission, IsDirectory, NotEmpty, IoError
- [x] Step(a) type — Continue/Halt for fold_while early termination
