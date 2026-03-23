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
├── specs/features/          # Per-feature documentation with source pointers
├── examples/                # Working example programs (actors, HTTP, debug, etc.)
├── tree-sitter-march/       # Zed editor extension (grammar.js + compiled march.dylib)
├── dune-project
├── bin/
│   └── main.ml              # parse → desugar → typecheck → eval + --compile + REPL JIT bootstrap
├── lib/
│   ├── ast/ast.ml           # Full AST: spans, exprs, patterns, decls, actors, session types
│   ├── lexer/lexer.mll      # ocamllex: atoms, pipes, do/end, when, etc.
│   ├── parser/parser.mly    # menhir: full expression grammar, fn head grouping, session types
│   ├── desugar/desugar.ml   # pipe desugar, multi-head fn → single EMatch clause
│   ├── typecheck/typecheck.ml  # 3389 lines: Bidirectional HM, linear types, session types,
│   │                           #   interface dispatch, pub/sig enforcement, cap hierarchy
│   ├── eval/eval.ml         # 4567 lines: Tree-walking interpreter, actors, Chan.send/recv,
│   │                         #   App.stop/lifecycle, supervision, session type eval
│   ├── effects/effects.ml   # Placeholder
│   ├── codegen/codegen.ml   # Placeholder
│   ├── errors/errors.ml     # Diagnostic type (Error/Warning/Hint + span)
│   ├── cas/                 # Content-addressed store
│   │   ├── cas.ml           # CAS object store (BLAKE3, 2-tier project+global cache)
│   │   ├── pipeline.ml      # Compilation pipeline (SCC → hash → cache)
│   │   ├── hash.ml          # BLAKE3 hashing helpers
│   │   ├── scc.ml           # Strongly-connected component analysis
│   │   └── serialize.ml     # Serialization for cache keys
│   ├── debug/               # Time-travel debugger
│   │   ├── debug.ml         # Debug context + dbg() handler
│   │   ├── debug_repl.ml    # Debug REPL (goto, diff, find, watch, replay)
│   │   ├── replay.ml        # Step replay engine
│   │   └── trace.ml         # Execution trace capture + actor history
│   ├── jit/
│   │   ├── jit_stubs.c      # C stubs for dlopen/dlsym/dlclose + call stubs
│   │   ├── jit.ml / jit.mli # OCaml externals wrapping C stubs
│   │   └── repl_jit.ml/mli  # Compile-and-dlopen REPL engine
│   ├── repl/                # Interactive REPL
│   │   ├── repl.ml          # 1478 lines: TUI + simple modes, eval loop, :commands
│   │   ├── tui.ml           # Two-pane notty TUI (input + scope panel)
│   │   ├── highlight.ml     # Syntax highlighting for live input
│   │   ├── input.ml         # Line editor state machine (kill ring, history nav)
│   │   ├── multiline.ml     # Continuation detection (do/end, fn, let blocks)
│   │   ├── history.ml       # Session history persistence
│   │   ├── complete.ml      # Tab completion (commands, keywords, in-scope names)
│   │   └── result_vars.ml   # `v` magic variable tracking
│   ├── scheduler/           # Cooperative + work-stealing scheduler
│   │   ├── scheduler.ml     # Reduction-counted preemption, run queue
│   │   ├── mailbox.ml       # Actor mailbox (bounded FIFO)
│   │   ├── task.ml          # Task (structured parallel compute) abstraction
│   │   └── work_pool.ml     # Work-stealing thread pool
│   └── tir/
│       ├── tir.ml           # ANF IR type definitions
│       ├── lower.ml         # 1277 lines: AST → TIR (ANF, pattern flattening, actors)
│       ├── mono.ml          # Monomorphization pass
│       ├── defun.ml         # Defunctionalization pass
│       ├── perceus.ml       # Perceus RC analysis
│       ├── escape.ml        # Escape analysis (stack promotion)
│       ├── opt.ml           # Optimization loop (fixed-point over passes)
│       ├── inline.ml        # Function inlining
│       ├── fold.ml          # Constant folding
│       ├── simplify.ml      # Algebraic simplification
│       ├── dce.ml           # Dead code elimination
│       ├── purity.ml        # Purity analysis (for inlining decisions)
│       ├── llvm_emit.ml     # 2021 lines: TIR → LLVM IR + REPL emission
│       └── pp.ml            # Pretty-printer
├── runtime/
│   ├── march_runtime.c/h    # Core runtime: alloc, RC, strings, actors, value_to_string
│   ├── march_http.c/h       # HTTP/WS runtime: TCP, HTTP parse/serialize, server, WebSocket
│   ├── sha1.c               # SHA-1 for WebSocket handshake
│   └── base64.c             # Base64 for WebSocket handshake
├── stdlib/                  # 21 modules, ~4894 lines
│   ├── prelude.march        # Auto-imported helpers (panic, identity, compose, unwrap, etc.)
│   ├── option.march         # Option(a) with Some/None
│   ├── result.march         # Result(a,e) with Ok/Err
│   ├── list.march           # 508 lines: map, filter, fold, zip, sort, etc.
│   ├── string.march         # 364 lines: String operations
│   ├── math.march           # 193 lines: transcendental functions, constants
│   ├── iolist.march         # 221 lines: lazy string builder
│   ├── seq.march            # 251 lines: lazy church-encoded fold sequences
│   ├── sort.march           # 615 lines: Timsort, Introsort, AlphaDev (n≤8)
│   ├── enum.march           # 314 lines: higher-level list utilities
│   ├── map.march            # 366 lines: AVL tree Map(k,v)
│   ├── path.march           # 91 lines: pure path manipulation
│   ├── file.march           # 139 lines: Result-based file I/O
│   ├── dir.march            # 50 lines: directory operations
│   ├── csv.march            # 100 lines: CSV parser (streaming + eager)
│   ├── http.march           # 338 lines: HTTP types (Method, Header, Request, Response)
│   ├── http_transport.march # 180 lines: Low-level TCP HTTP transport
│   ├── http_client.march    # 440 lines: High-level HTTP client with middleware pipeline
│   ├── http_server.march    # 233 lines: HTTP server types + pipeline runner
│   ├── websocket.march      # 52 lines: WebSocket types and frame operations
│   └── iterable.march       # 28 lines: placeholder Iterable interface
└── test/
    ├── test_march.ml         # 670 tests (6 failing: REPL JIT list literal issues)
    ├── test_cas.ml           # 41 tests (all passing: scc, pipeline, def_id)
    └── test_jit.ml           # 1 test (dlopen round-trip)
```

## Current State (as of 2026-03-22)

- **Builds clean**
- **694 tests across 3 suites; 6 failures (all in REPL JIT)**:
  - `test_march.exe`: 670 tests, 6 failures (repl_jit_regression 0,1,3,6,8 and repl_jit_cross_line 3 — all involve list literal JIT compilation)
  - `test_cas.exe`: 41 tests, all passing (scc, pipeline, def_id)
  - `test_jit.exe`: 1 test, passing (dlopen_libc)
- **Full pipeline working**: `dune exec march -- file.march` parses → desugars → typechecks → runs `main()` if present
- **`--dump-tir` flag**: prints TIR after full pipeline (Lower → Mono → Defun → Perceus → Escape); shows `stack_alloc` for promoted allocations
- **`--emit-llvm` flag**: emits textual LLVM IR to `<basename>.ll`; links with `runtime/march_runtime.c` via `clang` to produce native binaries
- **Compiled REPL**: `dune exec march` with no args launches a compile-and-dlopen REPL — each expression goes through the full TIR pipeline → LLVM IR → `clang -shared` → `.so` → `dlopen` → `dlsym` → call. Bindings persist as LLVM globals with `RTLD_GLOBAL`. Falls back to interpreter if JIT unavailable. `:quit`/`:env` commands; incremental env
- **Session types (binary, phases 1–3)**: `TChan` type + full `session_ty` representation (`SSend`/`SRecv`/`SChoose`/`SOffer`/`SRec`/`SEnd`/`SVar`/`SError`); `Chan.send`/`recv`/`close`/`choose`/`offer` special-cased in typecheck with linear channel advancement; duality verification for two-party protocols; `Chan.new(proto_name)` creates dual endpoints; protocol registry in typecheck env. Example: `examples/session_echo.march`
- **pub/sig enforcement**: Phase 1 visibility (`pub` on fn/type/ctor) enforced in `check_module` — private names are not exported to outer scope; Phase 2 sig conformance — `sig Name do ... end` checked against the actual `mod Name` implementation, missing declarations reported as errors
- **Bidirectional HM type checker**: 3389 lines; constructor registry, builtin `Some/None/Ok/Err`, named record type expansion, `Unit`/`Bool`/etc. annotation normalization, builtins (`print`, `println`, `int_to_string`, `bool_to_string`, etc.) in scope; actor declarations register message ctors and bind `state` in handler envs; interface dispatch wired (impl lookup + vtable-style call); capability hierarchy subtyping (`IO` → `IO.FileSystem` → etc.)
- **Tree-walking interpreter**: 4567 lines; `value` type (incl. `VPid`, `VChan`), pattern matching, `base_env` builtins, two-pass `eval_module_env` for mutual recursion; full synchronous actor runtime with `kill`/`is_alive`/drop semantics; `App.stop()`, `on_start`/`on_stop` lifecycle hooks, graceful shutdown + SIGTERM; supervision with epoch caps + task linking; `Chan.send`/`recv`/`close`/`choose`/`offer` evaluations; Drop handler support via `impl Drop`
- **Standard interfaces with auto-derivation**: `Eq`, `Show`, `Hash`, `Ord` — `derive Eq, Show for Color` syntax; desugar expands `DDeriving` to `DImpl` blocks; runtime dispatch via `impl_tbl` and `ctor_type_tbl`; `==`/`!=`/`<`/`<=`/`>`/`>=` and `show()`/`hash()`/`compare()` builtins dispatch through user impls for custom types; 18 new tests (670 total in test_march)
- **TIR pipeline** (`lib/tir/`):
  - `lower.ml` (1277 lines) — AST → ANF TIR, CPS let-insertion, nested pattern flattening, type_map threading, actor lowering
  - `mono.ml` (315 lines) — worklist monomorphization, name mangling (`identity$Int`), TVar elimination; `main` always seeded; function-as-value atoms via `ensure_atom_fns`; `ECallPtr` callee discovery
  - `defun.ml` (373 lines) — defunctionalization: lambda lifting, `$Clo_` struct generation, `ECallPtr` rewriting
  - `perceus.ml` (523 lines) — Perceus RC analysis: backwards liveness, `EIncRC`/`EDecRC`/`EFree` insertion, Inc/Dec cancel-pair elision, FBIP `EReuse` detection
  - `escape.ml` (279 lines) — Escape analysis: 3-phase intra-procedural stack promotion; `EAlloc` → `EStackAlloc` for non-escaping allocations
  - **Optimization loop** (`opt.ml`, 19 lines): fixed-point iteration over inline → fold → simplify → dce
    - `inline.ml` (179 lines) — function inlining (small, pure, single-use callees)
    - `fold.ml` (91 lines) — constant folding (arithmetic, boolean, string literals)
    - `simplify.ml` (107 lines) — algebraic simplification (identity ops, dead branches)
    - `dce.ml` (130 lines) — dead code elimination (unreachable lets, unused bindings)
    - `purity.ml` (25 lines) — purity analysis (used by inliner to gate side-effectful fns)
  - `llvm_emit.ml` (2021 lines) — TIR → textual LLVM IR; alloca+store+load for all let-bindings; ECase as switch+blocks+merge; arithmetic/cmp builtins to native ops; EAlloc→`@march_alloc`; EStackAlloc→`alloca`; EReuse→in-place write; REPL emission helpers; HTTP/WS extern declarations; float ops; string equality via `march_string_eq`; string pattern matching (if-else chains); closure wrappers; ~49 builtin function declarations
  - `pp.ml` — pretty-printer for all TIR types (incl. `stack_alloc`, `reuse`)
- **JIT / compile-and-dlopen** (`lib/jit/`):
  - `jit_stubs.c` — OCaml C stubs for POSIX `dlopen`/`dlsym`/`dlclose` + function pointer call stubs (void→ptr, void→void, void→i64, void→double, ptr→ptr)
  - `jit.ml` / `jit.mli` — OCaml externals wrapping the C stubs
  - `repl_jit.ml` / `repl_jit.mli` — Compiled REPL engine: TIR pipeline → LLVM IR → `clang -shared -fPIC` → `.so` → `dlopen` → call; tracks globals across fragments, deduplicates already-compiled functions, handles fn decls / let bindings / expressions
- **HTTP/WS C runtime** (`runtime/`):
  - `march_http.c` / `march_http.h` — TCP listen/accept/recv/send/close; HTTP request parsing and response serialization; thread-per-connection server accept loop; WebSocket handshake, frame recv/send, and select (with actor pipe support)
  - `sha1.c` — Minimal RFC 3174 SHA-1 for WebSocket handshake
  - `base64.c` — Minimal Base64 encoding for WebSocket handshake
- **C runtime builtins** — 49 compiled-path builtins: float (6), math (18), string (21), list (2), file/dir (2); all declared in `march_runtime.h` and registered in `llvm_emit.ml` + `defun.ml`
- **Pre-compiled runtime .so** — `ensure_runtime_so()` in `bin/main.ml` compiles `march_runtime.c` + `march_http.c` + `sha1.c` + `base64.c` to `~/.cache/march/libmarch_runtime.so`, cached and rebuilt only when sources change
- **Compiled HTTP server** — End-to-end working: `test_server.march` compiles to a native binary that listens on port 8787 and serves HTTP requests. Pipeline: March source → Parse → Desugar → Typecheck → Lower → Mono → Defun → Perceus → Escape → Opt → LLVM IR → clang → native binary. Closure-based pipeline dispatch with refcount borrowing for thread safety.
- **Three working examples**:
  - `examples/list_lib.march` — map, filter, fold, reverse, find, range (polymorphic list library)
  - `examples/actors.march` — Counter + Logger actors, normal messaging, kill, drop semantics, restart
  - `test_server.march` — Compiled HTTP server: `HttpServer.new(8787) |> HttpServer.plug(hello) |> HttpServer.listen()`
- **Content-addressed store** (`lib/cas/`): BLAKE3 hashing of definitions, 2-tier cache (project-local `.march/cas/` + global `~/.march/cas/`), SCC-aware pipeline, `def_id` type for hash-based identity; 41 tests passing
- **Cooperative scheduler** (`lib/scheduler/`): reduction-counted preemption (4000 reductions/quantum), work-stealing thread pool, actor mailboxes, `Task(a)` for structured parallel compute
- **Time-travel debugger** (`lib/debug/`): `dbg(expr)` breakpoints, step replay, actor history, `goto`/`diff`/`find`/`watch` commands, trace save/load; integrated with REPL via `on_dbg` callback
- **Full TUI REPL** (`lib/repl/`): 2197 lines; notty two-pane TUI with live syntax highlighting, tab completion, scope panel, actor monitoring; `v` magic variable (last result); `{ x with f = v }` record update hint; list pretty-printer; `:quit`/`:env`/`:help` commands; kill-ring line editing; multiline continuation detection
- **Actor system**: `spawn(ActorName)` / `send(pid, Msg(args))` → `Option(Unit)`, `kill(pid)`, `is_alive(pid)`, `{ state with field = ... }` record spread, synchronous inline dispatch; supervision (supervisor blocks, epoch caps, task linking); `App.stop()` with graceful SIGTERM shutdown; `on_start`/`on_stop` lifecycle hooks; process registry (`whereis`)
- **Zed editor extension** (`tree-sitter-march/`): grammar.js (12726 lines), compiled `march.dylib`, Tree-sitter queries, full syntax highlighting for all language constructs
- **Stdlib** (21 modules, 4894 lines): `prelude`, `option`, `result`, `list`, `string`, `math`, `iolist`, `seq`, `sort` (Timsort+Introsort+AlphaDev), `enum`, **`map`** (AVL tree), `path`, `file`, `dir`, `csv`, `http`, `http_transport`, `http_client`, `http_server`, `websocket`, `iterable`
- **Syntax additions**: `%` modulo, multi-statement match arm bodies, zero-arg constructor calls `Con()`, `state` as contextual keyword in expressions

## Known Failures (2026-03-22)

**6 failing REPL JIT tests** — all in `test/test_march.ml`, groups `repl_jit_regression` (0,1,3,6,8) and `repl_jit_cross_line` (3):
- "list literal compiles" — JIT compilation of `[1, 2, 3]` list literals fails
- "stdlib on list literal" — `List.length [1, 2, 3]` via JIT fails
- "stdlib List.length via prelude" — cross-line JIT test fails
- "stdlib chain" — chained stdlib calls fail under JIT
- "list pretty-print display" — list pretty-printing in JIT mode broken
- "general REPL interaction" — falls through list-related failure

Root cause: REPL JIT list literal codegen is broken. Non-JIT (interpreter) path works fine.

---

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
7. ~~**HTTP server stdlib**~~ ✓ — Full stdlib: `Http`, `HttpTransport`, `HttpClient`, `HttpServer`, `WebSocket`, `Csv` modules. Test server compiles and serves requests.
8. **Type-qualified constructor names** — `build_ctor_info` in `llvm_emit.ml` uses a flat hashtable keyed by constructor name; same-named constructors across types collide. Workaround: renamed colliding constructors (`Other`→`OtherKind`, `Timeout`→`ConnTimeout`, `ParseError`→`CsvParseError`/`ConnParseError`). Proper fix: type-qualify constructor keys.
9. **Atomic refcounting for threads** — Perceus RC ops are non-atomic; HTTP server works via explicit `inc_rc` borrowing before pipeline calls but general multi-threaded code needs atomic RC or a GC.
10. **Pipe desugar produces saturated calls** — Fixed: `a |> f(b)` now desugars to `f(a, b)` instead of curried `f(b)(a)`. Matches Elixir convention (piped value = first arg).

### Frontend / Ergonomics
4. **Fix REPL JIT list literal** — 6 failing tests; list literals in JIT (compile-and-dlopen) path break. Interpreter path is fine
5. **Typechecker: actor handler return type checking** — handlers should be verified to return the state record type
6. **String interpolation** — `${}` syntax, desugars to `Interpolatable` interface calls
7. **Type-qualified constructor names** — `build_ctor_info` in `llvm_emit.ml` uses flat hashtable; same-named ctors across types collide. Proper fix: type-qualify keys
8. **Atomic refcounting** — Perceus RC ops non-atomic; HTTP server works via explicit `inc_rc` borrowing but general multi-threaded code needs atomic RC or GC

## LLVM Codegen: End-to-End Compilation (2026-03-20)

First-ever compilation of a full March program (HTTP server with stdlib dependencies). Fixed ~15 codegen bugs:

- **Float literal emission**: OCaml `%h` → IEEE 754 hex via `Int64.bits_of_float`
- **Float comparisons**: `fcmp` instead of `icmp` when operands are `double`
- **Float negation**: `fneg double` for unary minus on floats
- **Boolean operators**: `&&`/`||`/`not` emitted inline as `and`/`or`/`xor i64`
- **String equality**: Detected `ptr`-typed `==`/`!=` → `march_string_eq` call
- **String pattern matching**: If-else chains with `march_string_eq` instead of `switch`
- **Double↔ptr coercion**: `bitcast` intermediary for case result slots
- **Closure wrappers**: Top-level functions used as first-class values wrapped in closure structs with trampolines
- **Mono seeding**: `main` always seeded; monomorphic callees enqueued on reference; function-as-value atoms discovered
- **Mono ECallPtr discovery**: Added handling so indirect call targets are specialized
- **Pipe desugar**: Changed from curried `f(b)(a)` to saturated `f(a, b)` (Elixir convention)
- **Constructor name collisions**: Renamed across stdlib (`Other`→`OtherKind`, `Timeout`→`ConnTimeout`, etc.)
- **49 C runtime builtins**: Float, math, string, list, file/dir functions
- **HTTP pipeline dispatch**: Closure-based invocation with refcount borrowing for thread safety

## Stdlib: File System (added 2026-03-20)
- [x] Path module — pure path manipulation (join, basename, dirname, extension, normalize)
- [x] Seq module — lazy church-encoded fold sequences (map, filter, take, drop, fold_while, etc.)
- [x] File module — Result-based I/O (read, write, append, delete, copy, rename, with_lines, with_chunks)
- [x] Dir module — directory operations (list, mkdir, mkdir_p, rmdir, rm_rf)
- [x] FileError ADT — NotFound, Permission, IsDirectory, NotEmpty, IoError
- [x] Step(a) type — Continue/Halt for fold_while early termination
