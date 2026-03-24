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
├── specs/progress.md        # This file
├── specs/todos.md           # Prioritised todo list
├── specs/features/          # Per-feature documentation with source pointers
│   ├── compiler-pipeline.md # TIR, defun, perceus, escape analysis, LLVM
│   ├── type-system.md       # HM inference, linear types, session types
│   ├── actor-system.md      # Actors, scheduler, mailbox, supervision
│   ├── content-addressed-system.md  # CAS, BLAKE3, pipeline
│   └── ...                  # (formatter, LSP, pattern-matching, repl, etc.)
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
│   ├── search/
│   │   └── search.ml        # Search index: Levenshtein fuzzy search, type/doc search, JSON cache
├── stdlib/                  # 29 modules, ~6200 lines
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
│   ├── hamt.march           # HAMT engine (generic 32-way trie, O(1) amortized)
│   ├── map.march            # HAMT-backed Map(k,v) — O(1) amortized lookup/insert/delete
│   ├── array.march          # Persistent vector (32-way trie + tail buffer)
│   ├── path.march           # 91 lines: pure path manipulation
│   ├── file.march           # 139 lines: Result-based file I/O
│   ├── dir.march            # 50 lines: directory operations
│   ├── csv.march            # 100 lines: CSV parser (streaming + eager)
│   ├── http.march           # 338 lines: HTTP types (Method, Header, Request, Response)
│   ├── http_transport.march # 180 lines: Low-level TCP HTTP transport
│   ├── http_client.march    # 440 lines: High-level HTTP client with middleware pipeline
│   ├── http_server.march    # 233 lines: HTTP server types + pipeline runner
│   ├── websocket.march      # 52 lines: WebSocket types and frame operations
│   ├── iterable.march       # 184 lines: map/filter/fold/take/drop/zip/enumerate/flat_map/any/all/find/count
│   ├── bytes.march          # Raw byte manipulation: from_string/to_string, hex, base64, UTF-8
│   ├── process.march        # OS process interaction: run, run_stream, env, cwd, argv, pid, exit
│   ├── logger.march         # Structured logging: Debug/Info/Warn/Error levels, context, log_with
│   ├── actor.march          # Actor helpers: cast (fire-and-forget), call (sync request/reply), reply
│   ├── flow.march           # Backpressure pipeline: Stage, from_list/range/unfold, map/filter/flat_map, collect/reduce
│   ├── random.march         # Pure PRNG: xoshiro256**, seed/next_int/next_float/next_bool/next_range/shuffle
│   ├── stats.march          # Descriptive statistics: mean/variance/std_dev/median/mode/percentile/correlation
│   ├── plot.march           # SVG chart generation: line/scatter/bar/histogram series, pure string building
│   └── docs/flow.md         # Flow module design doc: concepts, examples, GenStage comparison
├── test/
│   ├── test_march.ml         # 958+ tests (app entry, HAMT, tap, MPST, parity, LSP, opaque, type_level_nat, testing_library, bytes, logger, flow, actor_module, etc.)
│   ├── test_cas.ml           # 41 tests (scc, pipeline, def_id)
│   ├── test_jit.ml           # 1 test (dlopen round-trip)
│   ├── test_fmt.ml           # 23 tests (formatter round-trip)
│   ├── test_properties.ml    # 36 QCheck2 property tests
│   ├── test_supervision.ml   # 15 tests (actor supervision policies)
│   └── test_oracle.ml        # oracle tests (requires MARCH_BIN env var)
├── lsp/
│   └── test/test_lsp.ml      # 57 tests (initialize/diagnostics/hover/goto-def/completion/inlay hints)
└── forge/
    └── test/test_forge.exe   # 15 tests (scaffold, toml)
```

## Current State (as of 2026-03-24)

- **Builds clean**
- **1050 tests across 9 dune suites; 0 failures** (app entry point + HAMT Map/Set/Array + tap bus + REPL/compiler parity + MPST + REPL JIT fix + 5 new LSP features + tail-call enforcement + structural recursion refinement + stream fusion + type-level nat solver + built-in testing library + March-native stdlib tests + TCE structural recursion warning + Random/Stats/Plot stdlib + describe keyword + FFI interpreter dispatch + JIT bitwise builtins + doctest extraction + **TCO loop transformation in LLVM codegen**):
  - `test_march.exe`: 1050 tests, all passing (4 new `tco_codegen` tests)
  - `test_cas.exe`: 41 tests, passing (scc, pipeline, def_id)
  - `test_jit.exe`: 1 test, passing (dlopen_libc)
  - `test_fmt.exe`: 23 tests, passing (formatter round-trip)
  - `test_properties.exe`: 36 tests, passing (QCheck2 properties)
  - `test_supervision.exe`: 15 tests, passing (actor supervision)
  - `test_lsp.exe`: 85 tests, passing (doc strings, find-refs, rename, sig-help, code actions)
  - `test_stdlib_march.exe`: 7 tests, passing (Http, HttpTransport, HttpClient, HttpServer, WebSocket, Process, Logger)
  - `test_forge.exe`: 15 tests, passing (scaffold/toml)
  - `test_oracle.exe`: requires `MARCH_BIN` env var (oracle/idempotency/pass tests)
- **Full pipeline working**: `dune exec march -- file.march` parses → desugars → typechecks → runs `main()` if present
- **Match syntax**: `match expr do | Pat -> body end` (changed from `with` to `do` in 2026-03-21 — Elixir case-style)
- **String interpolation**: `${}` syntax fully implemented — `INTERP_START`/`INTERP_MID`/`INTERP_END` tokens in lexer; desugars to `++`/`to_string` chains (`lib/desugar/desugar.ml`)
- **Code formatter**: `march fmt [--check] <files>` — reformats source in-place (`lib/format/format.ml`, `bin/main.ml`)
- **Doctest extraction and execution** — `lib/doctest/doctest.ml` extracts `march>` examples from `fn_doc` strings; supports multi-line expressions (`...>` continuations), expected output matching, and panic expectations (`** panic: message`); `run_doctests` in `eval.ml` evaluates examples in the module environment; `march test` automatically runs doctests after regular tests per file; `stdlib/option.march` has 8 example doctests
- **JIT codegen: bitwise builtins** — `int_and/int_or/int_xor/int_not/int_shl/int_shr/int_popcount` now work in JIT; fixed missing `builtin_names` entry in `defun.ml` and added inline `EApp` cases in `llvm_emit.ml`
- **Built-in testing library**: `test "name" do...end` as first-class language construct; `assert expr` with compiler-assisted failure messages (shows LHS/RHS for binary comparisons); `setup do...end` (per-test hook) and `setup_all do...end` (once-before-all); `march test [--verbose] [--filter=pattern] [files...]` subcommand; dot mode by default, `--verbose` for full names; `forge test` delegates to `march test`; fully wired through all compiler passes; 13 tests in `testing_library` group
- **Property-based testing**: 36 QCheck2 properties in `test/test_properties.ml` — ADTs, closures, HOFs, tuples, strings, oracle/idempotency/pass properties
- **Standard Interfaces (Eq/Ord/Show/Hash) with derive syntax** — merged to main (from `claude/intelligent-austin`); `derive [Eq, Show]` syntax, eval dispatch for `==`/`show`/`hash`/`compare` via `impl_tbl`; 18 tests
- **LSP Server** (`march-lsp`) — diagnostics, hover (with doc strings), goto-def, completion, inlay hints, semantic tokens, actor info, find references, rename symbol, signature help, code actions (make-linear quickfix, exhaustion quickfix); uses `linol` framework; Zed extension wired up
- **LSP test suite** — `lsp/test/test_lsp.ml` (84 tests): position utils, diagnostics, document symbols, completions, goto-def, hover types, inlay hints, march-specific features, error recovery, analysis struct, doc strings, find references, rename symbol, signature help, code actions
- **Module alias declarations** — `alias Long.Module as Short` / `alias Long.Module` (last segment as alias); `DAlias` in AST; resolved in typecheck; unused-alias warning emitted
- **Pattern matching exhaustiveness checking** — compile-time pattern matrix analysis in `lib/typecheck/typecheck.ml`; warns on non-exhaustive matches, errors on unreachable arms
- **Multi-level `use` paths** — `use A.B.*` / `use A.B.C` fully supported; grammar ambiguity resolved in parser, full path resolution in typecheck
- **Opaque type enforcement** — `sig Name do type T end` hides representation; callers cannot access internal structure through the abstraction boundary
- **Multi-error parser recovery** — Menhir `error` token recovery; multiple syntax errors per file reported
- **Clojure-level REPL quality** — `:reload`, `:inspect/:i <expr>`, pretty-printer (depth/collection truncation), error recovery (env preserved on typecheck error), REPL/compiler parity tests
- **`tap` builtin** — `tap(v)` sends `v` to a global thread-safe tap bus and returns `v`; REPL drains and displays tapped values after each eval (orange in TUI, `tap> v` in simple mode). Type: `∀a. a → a`. Safe for actor-context use.
- **REPL/compiler parity harness** — `check_parity` helper + `repl_compiler_parity` test group; runs expressions through both interpreter and JIT, compares outputs; JIT tests skip gracefully when clang is absent
- **Stream fusion / deforestation** — `lib/tir/fusion.ml` TIR optimization pass fuses chains of `map/filter/fold` into single-loop functions with no intermediate list allocations; runs after monomorphization before defunctionalization; handles 2-step (`map+fold`, `filter+fold`) and 3-step (`map+filter+fold`) chains; guards against multi-use intermediates and impure operations; 9 tests
- **Type-qualified constructor names** — `build_ctor_info` in `llvm_emit.ml` uses `(type_name, ctor_name)` pairs; constructor collisions across ADTs eliminated
- **Actor handler return type checking** — handlers statically verified to return correct state record type
- **Linear/affine propagation through record fields** — `EField` access on a linear field consumes it; `EUpdate` respects per-field linearity
- **Field-index map for records** — `field_index_for` in `llvm_emit.ml` (line 762); all field GEP offsets correct
- **Atomic refcounting** — C11 atomics (`atomic_fetch_add/sub_explicit`) in `march_runtime.c`; RC thread-safe
- **Actor TIR lowering** — `lower_actor` in `lib/tir/lower.ml`; actors compile to native code via `ESpawn`/`ESend` lowering
- **Type-level natural number constraint solver (v1)** — `normalize_tnat` reduces concrete arithmetic (`2+3→5`, `(1+2)*3→9`) and identity/annihilation rules (`n+0→n`, `n*0→0`, `n*1→n`); `solve_nat_eq` in `unify` solves linear equations (`a+2=5 → a=3`, `a*k=n` when divisible); parser extended with `ty_nat_add`/`ty_nat_mul` levels and integer literals in type position; 9 tests in `type_level_nat` group
- **SRec recursive protocol unfolding** — `unfold_srec` in typecheck.ml; recursive session types handled; 6 new multi-turn tests (ping-pong loop, nested SRec, SChoose inside SRec, wrong type in loop)
- **Multi-party session types (MPST)** — `SMSend(role, T, S)` / `SMRecv(role, T, S)` role-annotated session type constructors; `project_steps` projects global choreography to each role's local type; MPST mergeability check for non-chooser roles in `ProtoChoice` (via `session_ty_exact_equal`); `MPST.new` creates N linear `TChan` endpoints (requires ≥3 roles); `MPST.send(ch, Role, v)` / `MPST.recv(ch, Role)` / `MPST.close(ch)` all type-checked at compile time; runtime pairwise queue routing (N*(N-1) directed queues shared between endpoints); 21 new tests (parsing, projection, type check ok/error, eval: 3-party auth, relay, 4-party chain, recv-before-send error)
- **Type error pretty-printing** — `pp_ty_pretty` wraps long type expressions at 60 chars with indented args; `report_mismatch` shows multi-line format for types >50 chars; `find_arg_mismatch` adds contextual notes identifying which arg/field differs
- **Forge build tool** — `forge/` package: `forge new/build/run/test/format/interactive/i/clean/deps`; scaffold generates valid March (PascalCase module names, `do/end` fn bodies, `println` builtin, test file with `main()`); 15 tests in `forge/test/test_forge.ml`
- **Tail-Call Optimization (TCO) — loop transformation in LLVM IR** — `lib/tir/llvm_emit.ml` detects self-tail-recursive functions at codegen time (`has_self_tail_call` traversal), then transforms the emission: inserts a `tco_loop` header block, replaces tail self-calls with stores to parameter alloca slots + `br label %tco_loop` back-edge, and opens a dead block for any IR emitted by callers after the terminator. LLVM's mem2reg + DCE produce tight loop code. Guarantees O(1) stack space for tail-recursive functions at the compiled-code level. 4 new `tco_codegen` IR-level tests (factorial, fold, non-tail fib, countdown).

- **Mandatory tail-call enforcement (refined with structural recursion)** — after typechecking, every recursive function is statically checked to be either tail-recursive or structurally recursive. Tarjan's SCC detects mutual recursion; `check_tail_position` verifies each non-tail recursive call: if any argument is a pattern-bound sub-component of a parameter (e.g., `l`, `r` from `Node(l, r)`) or an arithmetic reduction (`n-1`, `n-2`), the call is allowed. Truly unbounded non-tail recursion (same argument, no reduction) still errors. Non-tail errors include function name, call-site span, wrapping context, and accumulator hint. All stdlib recursive functions rewritten with accumulators/path-stacks. 15 `tail_recursion` tests. Fixes fib, binary-trees, and tree-transform benchmarks.
- **HAMT persistent data structures** — `stdlib/hamt.march` (generic 32-way HAMT engine); `stdlib/map.march` rewritten with HAMT (O(1) amortized); `stdlib/set.march` rewritten with HAMT; `stdlib/array.march` added (persistent vector, 32-way trie + tail buffer, O(1) amortized push/pop). 26 new tests.
- **`Set` module** — `stdlib/set.march` (HAMT-backed, full API: insert/remove/contains/union/intersection/difference/fold)
- **`BigInt` / `Decimal`** — `stdlib/bigint.march`, `stdlib/decimal.march`
- **`Iterable` interface expansion** — 184 lines in `stdlib/iterable.march`; map/filter/fold/take/drop/zip/enumerate/flat_map/any/all/find/count
- **Property tests for Eq/Ord/Show/Hash** — QCheck2 properties (reflexivity, symmetry, transitivity, hash consistency)
- **Parser fuzz tests** — 19 structural fuzz cases in `parser_fuzz` test group
- **Supervisor restart policies** — `sc_max_restarts` sliding window enforced in eval.ml
- **REPL JIT `compiled_fns` corruption fix** — `partition_fns` in `repl_jit.ml` now pure (no side effects); `mark_compiled_fns` called only after successful `compile_fragment` + dlopen; prevents stdlib fn "undefined symbol" cascade when any prior fragment compilation failed
- **`app` entry point (Phase 1 interpreter)** — `APP`/`ON_START`/`ON_STOP` lexer tokens; `DApp` AST node; `app_decl` parser rule; desugar converts `DApp` → `__app_init__` function with `SupervisorSpec` return type annotation; mutual-exclusivity check (compile error if both `main` + `app` defined); `spawn_from_spec` spawns actor tree; `run_module` dispatches on `__app_init__`; SIGTERM/SIGINT signal handlers; graceful reverse-order shutdown; process registry (`whereis`/`whereis_bang`); named children; `on_start`/`on_stop` lifecycle hooks; dynamic supervisors (`dynamic_supervisor`, `start_child`, `stop_child`, `which_children`, `count_children`). 45 tests across `app`, `shutdown`, `registry`, `dynamic_supervisor`, `spec_construction`, and `app_shutdown` groups.
- **Cross-language benchmarks** — `bench/elixir/`, `bench/ocaml/`, `bench/rust/` contain idiomatic implementations of fib(40), binary-trees(15), tree-transform(depth=20×100), and list-ops(1M); `bench/run_benchmarks.sh` compiles all, runs N times, reports median/min/max; results in `bench/RESULTS.md`. **All four benchmarks compile and run (2026-03-23):** fib 288 ms ≈ Rust; tree-transform 524 ms (**7.3–19× faster** than OCaml/Rust via Perceus FBIP); binary-trees 275 ms (OCaml wins at 20 ms with generational GC); list-ops ~76 ms (stream fusion: was 117 ms pre-fusion).
- **stdlib: Random module** — `stdlib/random.march`: purely-functional PRNG using xoshiro256** algorithm adapted for 63-bit OCaml integers; `Rng` record state (4 × 63-bit integers); `seed` (SplitMix-inspired hash expansion), `next_int`, `next_float`, `next_bool`, `next_range`, `shuffle`; all pure (take `Rng`, return `(value, Rng)`); no global mutable state.
- **stdlib: Stats module** — `stdlib/stats.march`: descriptive statistics over `List(Float)`; `mean`, `variance`, `std_dev`, `median`, `mode`, `min`, `max`, `range`, `percentile`, `covariance`, `pearson_correlation`; pure functional, no external dependencies.
- **stdlib: Plot module** — `stdlib/plot.march`: SVG chart generation; `Color`/`Style`/`Series`/`Chart` types; `line_series`/`scatter_series`/`bar_series`/`histogram_series`; `new`/`add_series`/`set_title`/`set_size`/`set_padding`/`to_svg`; self-contained pure March string building, no external dependencies.
- **`describe` keyword for test grouping** — `describe "name" do ... end` groups tests under a label with prefix propagation (e.g. `"auth login success"`); `DESCRIBE` lexer token; `DDescribe` AST node; fully wired through lexer, parser, desugar, typecheck, eval, TIR lower, formatter, and LSP analysis.
- **FFI interpreter dispatch** — `VForeign(lib, sym)` value type in `eval.ml`; `foreign_stubs` hashtable maps `(lib_name, symbol_name)` to OCaml stubs; `DExtern` in `eval_decl` binds extern functions to `VForeign` stubs; `apply_inner` dispatches `VForeign` via stub table; 25 math/libc stubs pre-registered (`sqrt`, `sin`, `cos`, `pow`, `atan2`, etc. across `"c"`/`"m"`/`"libm"` library names); `puts` stub registered; `declared_names` and `make_recursive_env` updated to include extern bindings.

### Known Implementation Gaps

- **Epoch-based capability revocation** — `send(cap, msg)` does not validate the epoch against a revocation list. `Cap(A, e)` epoch is carried in the type but not checked at runtime.
- **`rest_for_one`/`one_for_all` supervisor strategies** — only `one_for_one` is implemented; the other OTP-style restart strategies are not yet handled.
- **Actor compilation tests** — need `dune runtest`-level tests for compiled actor programs.

## Known Failures (2026-03-24)

**8 failures** in `test_march.exe`, all in the `repl_jit_regression` and `repl_jit_cross_line` test groups:

- `repl_jit_regression` 0, 1, 3, 4, 6, 9, 11 — list literal compilation, stdlib on list literal, stdlib chain, list pretty-print, general REPL interaction
- `repl_jit_cross_line` 3 — stdlib `List.length` across lines

These are JIT-mode REPL tests that require `clang` to compile `.so` fragments. All other 990 tests pass.

---

## Resolved Open Questions

- **Compilation target**: LLVM
- **MPST scope**: Multi-party session types implemented (N≥3 participants, pairwise queue routing)
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
1. ~~**Perceus RC Analysis**~~ ✓ — `lib/tir/perceus.ml` complete. Documented in `specs/features/compiler-pipeline.md`.
2. ~~**Escape Analysis**~~ ✓ — `lib/tir/escape.ml` complete. Documented in `specs/features/compiler-pipeline.md`.
3. ~~**LLVM IR emission**~~ ✓ — `lib/tir/llvm_emit.ml` + `runtime/march_runtime.{c,h}`. `march --emit-llvm file.march` produces `.ll`; link with `clang runtime/march_runtime.c file.ll -o bin`. Verified: `escape_test.march` compiles to native binary printing `7`.

### Next milestones
4. ~~**Field-index map for records**~~ ✓ — `field_index_for` in `llvm_emit.ml` (line 762) handles all fields.
5. ~~**`llc` / `clang` invocation from compiler**~~ ✓ — `march --compile` calls clang automatically; `ensure_runtime_so()` pre-compiles runtime to cached `.so`.
6. ~~**Type-qualified constructor names**~~ ✓ — `build_ctor_info` keyed by `(type_name, ctor_name)` pairs.
7. ~~**Atomic refcounting**~~ ✓ — C11 atomics in `march_runtime.c`.
8. ~~**Actor compilation tests**~~ ✓ — 8 tests in `actor_compile` group verifying LLVM IR for actor programs.
9. ~~**HAMT implementation**~~ ✓ — `stdlib/hamt.march` + HAMT-backed `Map`/`Set` + persistent `Array`; 26 new tests.
10. ~~**LSP feature improvements**~~ ✓ — 5 new features merged; 84 LSP tests total.

### Frontend / Ergonomics
1. ~~**Fix REPL JIT list literal**~~ — 8 repl_jit failures remain (see Known Failures).
2. ~~**Actor handler return type checking**~~ ✓ — gap checks in typecheck.
3. ~~**Type-qualified constructor names**~~ ✓ — done.
4. ~~**Atomic refcounting**~~ ✓ — done.
5. ~~**Pattern matching exhaustiveness checking**~~ ✓ — done.
6. ~~**Multi-level use paths**~~ ✓ — done.
7. ~~**Merge Standard Interfaces branch**~~ ✓ — merged.
8. ~~**Merge LSP branch**~~ ✓ — merged (57-test suite).
9. ~~**`tap>` async value inspector**~~ ✓ — done (`tap` builtin, thread-safe bus, REPL drains after each eval).
10. ~~**`app` entry point**~~ ✓ — done (Phase 1 interpreter: parser, desugar, typecheck annotation, eval, shutdown, registry, dynamic supervisors).

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
