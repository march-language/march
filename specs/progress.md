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
│   ├── march_http_evloop.c  # Event-loop HTTP server: kqueue (macOS) / epoll (Linux), SO_REUSEPORT
│   ├── march_http_io.c/h    # Non-blocking recv/send state machines + per-thread conn_state pool
│   ├── march_http_internal.h # Shared internals between march_http.c and march_http_evloop.c
│   ├── march_http_parse_simd.c/h  # SIMD-accelerated HTTP/1.x parser (SSE4.2 fast path + scalar fallback)
│   ├── march_http_response.c/h    # Zero-copy response builder (iovec + writev, cached Date header)
│   ├── march_heap.c/h       # Phase 5: per-process bump-pointer arena allocator
│   ├── march_message.c/h    # Phase 5: cross-heap copy/move, MPSC mailbox, selective receive
│   ├── march_gc.c/h         # Phase 5: semi-space copying GC (per-process, no global pause)
│   ├── sha1.c               # SHA-1 for WebSocket handshake
│   └── base64.c             # Base64 for WebSocket handshake
│   ├── search/
│   │   └── search.ml        # Search index: Levenshtein fuzzy search, type/doc search, JSON cache
├── stdlib/                  # 34 modules, ~7500 lines
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
│   ├── pubsub.march         # 222 lines: sharded PubSub backbone (subscribe/unsubscribe/broadcast, topic_matches, topic_shard)
│   ├── channel.march        # 357 lines: Socket type, HandleResult, ChannelMsg/Route, wire serialization/parsing
│   ├── channel_server.march # 263 lines: ChannelMailbox, JoinResult, ChannelConfig, do_join/leave, apply_result, shard helpers
│   ├── presence.march       # 281 lines: PresenceMeta/Entry/State, track_state/untrack_state/list_state, diff helpers
│   ├── channel_socket.march # 287 lines: SocketConfig, ActiveChannels registry, topic routing, plug_for/ws_loop
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
    ├── lib/
    │   ├── resolver_version.ml       # semver parse/compare/~> constraint expansion
    │   ├── resolver_constraint.ml    # constraint types, satisfies, AND combinator
    │   ├── resolver_lockfile.ml      # forge.lock TOML write/read, drift detection
    │   ├── resolver_registry.ml      # in-memory package index, TOML load/save
    │   ├── resolver_pubgrub.ml       # PubGrub greedy solver, conflict messages
    │   ├── resolver_cas_package.ml   # canonical archive, SHA-256 CAS store/verify
    │   ├── resolver_api_surface.ml   # pub fn/type extraction, diff, semver check
    │   ├── cmd_deps.ml               # forge deps (install all dep types + [patch])
    │   └── cmd_publish.ml            # forge publish with semver enforcement
    └── test/
        ├── test_forge.exe            # 15 tests (scaffold, toml)
        ├── test_resolver.exe         # 35 tests (semver, constraints, lockfile)
        ├── test_solver.exe           # 16 tests (registry, PubGrub solver)
        ├── test_cas_package.exe      # 10 tests (canonical archive, CAS)
        ├── test_patch.exe            # 6 tests ([patch] overrides)
        ├── test_api_surface.exe      # 25 tests (API extraction, semver enforcement)
        ├── test_properties.exe       # 3 QCheck properties (solver soundness)
        ├── test_regression.exe       # 8 tests (Cargo/Hex/npm regressions)
        └── bench_solver.exe          # performance: chain-500/diamond-20×20 benchmarks
```

## Current State (as of 2026-03-27, post Html template system — partials, collections, layouts, IOList.hash, html_auto_escape)

- **Builds clean**
- **0 known failures** across all test suites (app entry point + HAMT Map/Set/Array + tap bus + REPL/compiler parity + MPST + REPL JIT fix + LSP Phase 1 + LSP Phase 2 + tail-call enforcement + structural recursion refinement + stream fusion + type-level nat solver + built-in testing library + March-native stdlib tests + TCE structural recursion warning + Random/Stats/Plot stdlib + describe keyword + FFI interpreter dispatch + JIT bitwise builtins + doctest extraction + **TCO loop transformation in LLVM codegen** + **DataFrame Phase 7** + **constant propagation** + **Mutual TCO** + **borrow inference** + **known-call** + **struct update fusion** + **escape analysis** + **Phase 5: per-process heaps + message passing** + **Phase 4: reduction counting in compiled code** + **Phase 4: lazy stack growth** + **Vault sharded KV store**):
  - `test_march.exe`: 1151 tests, 0 failures
  - `test_cas.exe`: 41 tests, passing (scc, pipeline, def_id)
  - `test_jit.exe`: 1 test, passing (dlopen_libc)
  - `test_fmt.exe`: 23 tests (23 failures: pre-existing formatter round-trip failures)
  - `test_properties.exe`: 36 tests, passing (QCheck2 properties)
  - `test_supervision.exe`: 15 tests, passing (actor supervision)
  - `test_lsp.exe`: 120 tests, passing (doc strings, find-refs, rename, sig-help, code actions, snippet completions, folding ranges, type annotation action, remove unused binding action, phase2 enhanced match, quickfix framework, dead code detection, p1.1 typed match stubs, p1.7 fn return/param annotation, batch annotation, P2.8 naming convention fix, P3.10 De Morgan rewrite)
  - `test_stdlib_march.exe`: 13 tests, passing (Http, HttpTransport, HttpClient, HttpServer, WebSocket, Tls, Process, Logger, PubSub, Channel, ChannelServer, Presence, ChannelSocket)
  - `test_forge.exe`: 15 tests, passing (scaffold/toml)
  - `test_resolver.exe`: 35 tests, passing (semver version parse/compare/~>, constraints, project dep loading, lockfile write/read/drift)
  - `test_solver.exe`: 16 tests, passing (registry roundtrip, PubGrub solver happy paths + conflicts + error messages)
  - `test_cas_package.exe`: 10 tests, passing (canonical archive, CAS store/lookup/idempotency/verify/tampering detection)
  - `test_patch.exe`: 6 tests, passing ([patch] overrides parse + solver wiring)
  - `test_api_surface.exe`: 25 tests, passing (pub fn/type extraction, surface diff, semver bump classification, forge publish enforcement)
  - `test_properties.exe` (forge): 3 QCheck property tests × 200 cases each (solution satisfies constraints, solver deterministic, no violated transitive constraints)
  - `test_regression.exe`: 8 tests, passing (Cargo/Hex/npm regression scenarios; greedy backtrack limitation documented)
  - `test_oracle.exe`: requires `MARCH_BIN` env var (oracle/idempotency/pass tests)
- **Full pipeline working**: `dune exec march -- file.march` parses → desugars → typechecks → runs `main()` if present
- **Match syntax**: `match expr do Pat -> body end` — no leading `|` on arms; NL separates arms inside match body; multi-statement arms use `-> do ... end` wrapper (2026-03-26 syntax overhaul)
- **String interpolation**: `${}` syntax fully implemented — `INTERP_START`/`INTERP_MID`/`INTERP_END` tokens in lexer; desugars to `++`/`to_string` chains (`lib/desugar/desugar.ml`)
- **Code formatter**: `march fmt [--check] <files>` — reformats source in-place (`lib/format/format.ml`, `bin/main.ml`)
- **Doctest extraction and execution** — `lib/doctest/doctest.ml` extracts `march>` examples from `fn_doc` strings; supports multi-line expressions (`...>` continuations), expected output matching, and panic expectations (`** panic: message`); `run_doctests` in `eval.ml` evaluates examples in the module environment; `march test` automatically runs doctests after regular tests per file; `stdlib/option.march` has 8 example doctests
- **JIT codegen: bitwise builtins** — `int_and/int_or/int_xor/int_not/int_shl/int_shr/int_popcount` now work in JIT; fixed missing `builtin_names` entry in `defun.ml` and added inline `EApp` cases in `llvm_emit.ml`
- **Built-in testing library**: `test "name" do...end` as first-class language construct; `assert expr` with compiler-assisted failure messages (shows LHS/RHS for binary comparisons); `setup do...end` (per-test hook) and `setup_all do...end` (once-before-all); `march test [--verbose] [--filter=pattern] [files...]` subcommand; dot mode by default, `--verbose` for full names; `forge test` delegates to `march test`; fully wired through all compiler passes; 13 tests in `testing_library` group
- **Property-based testing**: 36 QCheck2 properties in `test/test_properties.ml` — ADTs, closures, HOFs, tuples, strings, oracle/idempotency/pass properties
- **Standard Interfaces (Eq/Ord/Show/Hash) with derive syntax** — merged to main (from `claude/intelligent-austin`); `derive [Eq, Show]` syntax, eval dispatch for `==`/`show`/`hash`/`compare` via `impl_tbl`; 18 tests
- **Known-call optimization + struct update fusion** — `lib/tir/known_call.ml`: after Defun, converts `ECallPtr(AVar clo, args)` → `EApp(apply_fn, clo :: args)` for closures bound by a statically-visible `EAlloc`/`EStackAlloc` in scope (tracks `$Clo_`-prefixed names). Runs between Defun and Perceus (so apply functions are still pure and inlinable), and again in the Opt fixed-point loop. `inline.ml` size threshold raised 15→50 to cover medium-sized HTTP helper functions. `Fusion.run_struct` in `lib/tir/fusion.ml`: merges chains of single-use `EUpdate` operations (`let v2 = {v1|f1}; let v3 = {v2|f2} → let v3 = {v1|f1,f2}`); later writes win on field conflicts; handles 3+-step chains via the fixed-point loop. Both passes added to `opt.ml` coordinator. 8 new tests: `known_call` × 4, `struct_fusion` × 4.
- **LSP Performance Insights plan** — `specs/plans/lsp-performance-insights-plan.md`: 3-phase plan for surfacing compiler optimization knowledge as Elm-style plain-English diagnostics. Phase 1 (AST-level, no new infrastructure): TCO blocking detection with accumulator suggestion, actor message copy warning for non-linear sends, closure capture size hints. Phase 2 (AST heuristics): reuse opportunity via `refs_map` use-count, indirect call detection, allocation-in-recursive-arm warning. Phase 3 (async TIR pipeline): stack vs heap via EStackAlloc, precise reuse via EReuse, confirmed direct calls via known_call. Includes `perf_insight` type design, display mechanisms (diagnostics/inlay hints/hover/code lens), style guide (Elm-style, no compiler jargon, always actionable).
- **LSP code actions P2.8 + P3.10** — (P2.8) Case correction: `is_camel_case` + `camel_to_snake` helpers detect camelCase function names; `naming_violation` record (`nv_name`, `nv_suggested`, `nv_span`, `nv_kind`); `collect_naming_decl` recursively walks `DFn`/`DMod` in `user_decls`; `code_actions_at` offers "Rename function to `snake_case`" `RefactorRewrite` using the existing `rename_at` infrastructure (updates all references). (P3.10) De Morgan rewrite: `demorgan_site` record (`dm_span`, `dm_form`, `dm_left_span`, `dm_right_span`); `collect_dm_expr` walks all expressions detecting `!(a && b)` → `NegatedBinop "&&"`, `!(a || b)` → `NegatedBinop "||"`, `!a && !b` → `PairOfNegs "&&"`, `!a || !b` → `PairOfNegs "||"`; `code_actions_at` offers "Apply De Morgan: ..." `RefactorRewrite` with correct dual-operator rewrite. +13 LSP tests.
- **LSP forge.toml dep resolution** — the LSP now reads `forge.toml` from the project root (walked up from the open file) and resolves `[deps]` entries to their `lib/` directories, mirroring exactly what `forge build` injects into `MARCH_LIB_PATH`. Both path-dep (`path = "../bastion"`) and git-dep (`git = "..."`, resolved via `~/.march/cas/deps/<name>`) are supported. Dep modules are loaded as `DMod` nodes before user code so the type-checker can resolve cross-dep imports. `MARCH_LIB_PATH` env var is still honoured as a fallback. Changes: `lsp/lib/forge_config.ml` (new — self-contained TOML parser + dep resolver), `lsp/lib/analysis.ml` (call `March_resolver.Resolver.resolve_imports ~extra_lib_paths`), `lib/resolver/resolver.ml` (new `~extra_lib_paths:[]` optional param), `lsp/lib/dune` (add `march_resolver` dep).
- **LSP Server** (`march-lsp`) — diagnostics, hover (with doc strings), goto-def, completion, inlay hints, semantic tokens, actor info, find references, rename symbol, signature help, code actions (make-linear quickfix, exhaustion quickfix); uses `linol` framework; Zed extension wired up
- **LSP P1.1 + P1.7 code action enhancements** — (1) Typed match stubs: `match_site.ms_ctor_sigs` maps missing ctors to surface arg types; `arm_text_for_case` generates `| Ctor(field1, field2) -> ?` stubs with type-derived names (Int→n, String→s, List→items, etc.); nullary ctors stay bare. (2) Enhanced type annotations: new `annotation_kind` type distinguishes `AnnLet | AnnFnReturn | AnnFnParam`; `collect_annotation_sites` extended for `DFn` nodes — `AnnFnReturn` when no `fn_ret_ty` present (inserts `-> T` before `do`), `AnnFnParam` for bare `FPPat(PatVar)` params (inserts `: T` after param name); batch "Annotate all N bindings" action when 2+ AnnLet sites in file. +9 LSP tests (107 total).
- **LSP Phase 2 enhancements** — (1) Enhanced exhaustive match: `match_site.ms_missing_cases : string list` holds ALL missing variants (AST-based `augment_match_sites` pass enumerates type ctors, filters covered constructors, skips qualified `Bit.Zero` keys); "Add all N missing cases" bulk `QuickFix`; "Fix all incomplete `T` matches in file" `RefactorRewrite` when same type appears in multiple match sites; `type_matches` groups match sites by type. (2) Diagnostics-driven quickfix framework: `fix_registry : (string, fix_gen) Hashtbl.t` with `register_fix`/`apply_fix_registry`; pre-registered codes: `non_exhaustive_match`, `unused_binding`, `unused_private_fn`, `unreachable_code`. (3) Dead code detection: call-graph BFS from public roots + `main`; `unused_fns : string list`; `unused_private_fn` Warning diagnostics; post-block scanner emits `unreachable_code` Warning for expressions following `panic`/`panic_`/`unreachable_` calls. +9 tests.
- **LSP Phase 1 enhancements** — (1) Snippet completions: `insertText` with tabstops for functions (`"fn(${1:Int}, ${2:String})"`) and multi-arg constructors; `insertTextFormat=Snippet`. (2) Folding ranges: `textDocument/foldingRange` handler; `collect_fold_ranges` walks `DFn`/`DMod`/`DActor`/`DDescribe`/`EMatch`/`ELetFn`; `foldingRangeProvider=true`. (3) Add type annotation code action: `collect_annotation_sites` finds untyped `ELet`/`DLet` bindings; `RefactorRewrite` inserts `": TypeName"`. (4) Remove unused binding code action: `code : string option` on `Errors.diagnostic`; `warning_with_code ~code:"unused_binding"`; generates "Prefix with underscore" and "Remove unused binding" `QuickFix` actions. +4 tests.
- **LSP test suite** — `lsp/test/test_lsp.ml` (107 tests): position utils, diagnostics, document symbols, completions, goto-def, hover types, inlay hints, march-specific features, error recovery, analysis struct, doc strings, find references, rename symbol, signature help, code actions, snippet completions, folding ranges, type annotation action, remove unused binding action, phase2 enhanced match, quickfix framework, dead code detection, p1.1 typed match stubs, p1.7 fn return/param annotation, p1.7 batch annotation
- **Escape analysis tests** — `escape_analysis` group in `test/test_march.ml` (6 tests): `escape_module` helper runs Lower→Mono→Defun→Perceus→Escape pipeline; tests verify: locally-discarded EAlloc promoted to EStackAlloc; returned value stays EAlloc; value stored in another alloc stays EAlloc; Conn-pattern (field read via match, field returned not struct) promotes to EStackAlloc; EDecRC eliminated for promoted variables; complex multi-alloc function runs without crash.
- **FBIP reuse now fires correctly** — Fixed borrow inference (`lib/tir/borrow.ml`) to treat case scrutinee as owning when branch bodies allocate same-type constructors (the "reconstruct" pattern). Added `has_matching_alloc` helper. This enables Perceus FBIP to detect DecRC→EAlloc of matching shape and replace with EReuse (in-place mutation). `tree_transform` benchmark: 10.6s → 0.52s (20× speedup), 92MB → 66MB RSS.
- **Perceus post-call DecRC correctness fix** — Fixed `lib/tir/perceus.ml` where borrow inference's post-call DecRC for borrowed args (emitted as `ESeq(call, DecRC(arg))`) discarded the call's return value because `ESeq` returns the last expression. Added `fix_tail_value` restructuring pass: introduces fresh let binding to preserve the call result (`ELet($rc_N, call, ESeq(DecRC(arg), $rc_N))`). Follows ELet chains to fix nested patterns. Fixes correctness bugs in `binary_trees`, `list_ops`, `tree_transform`, and any function returning a value from a callee that borrows its argument.
- **Green thread lazy stack growth (Phase 4)** — `runtime/march_scheduler.{h,c}`: each process reserves `MARCH_STACK_MAX` (1 MiB) + 1 guard page as `PROT_NONE` via `stack_alloc_lazy()`; only the top `MARCH_STACK_INITIAL` (4 KiB) starts accessible. `march_sigsegv_handler` installed with `SA_SIGINFO | SA_ONSTACK`: on guard-page fault checks `si_code == SEGV_ACCERR`, identifies the running process via thread-local `tl_sched->current`, calls `mprotect` to extend accessibility from the faulting page to the current usable bottom, then returns for CPU retry. Per-scheduler-thread 64 KiB alternate signal stack (`sigaltstack`) set up in `sched_loop()`. `p->stack_mmap_base` field stores the reservation base for `munmap` on process death; `p->stack_base` tracks current usable bottom and decreases as the stack grows. Old `stack_free(base, alloc)` replaced by direct `munmap(mmap_base, alloc)`. 2 new C tests: `test_stack_growth_deep` (one process ≈10 KiB stack use > 4 KiB initial), `test_stack_growth_many` (50 concurrent processes each ≈10 KiB). All 10 Phase 1+2+4 scheduler tests pass.
- **Perceus closure-FV RC exemption (_closure_fvs)** — Fixed a data race in concurrent HTTP: apply functions (closures) loaded FV variables from `$clo` via EField and then emitted a non-atomic `march_decrc_local` on them after a borrow call, racing with the C HTTP runtime's atomic `march_incrc` per-request incref. Root cause: Perceus treated closure-captured variables as callee-owned, inserting `post_dec_vars` decrefs and `dead-binding` decrefs that the apply function has no right to emit (the closure's RC keeps FVs alive). Fix: `collect_closure_fvs` scans the function body for `let fv = $clo.$fvN` bindings before `insert_rc`; these names are collected into `_closure_fvs` (module-level ref, cleared per function). All three Perceus RC mechanisms skip variables in `_closure_fvs`: `find_inc_vars` (no EIncRC for FVs passed as args), `post_dec_vars` in EApp (no EDecRC after borrow calls), and ELet dead-binding (no EDecRC/EFree for unused FV bindings). C runtime updated: removed per-request plugs-list incref loop from `connection_thread` (lines that iterated `clo+24` and called `march_incrc` on each Cons node and handler). Result: `http_hello` handles **53 k req/s with 100 concurrent connections** without use-after-free crashes. All 1321 OCaml tests still pass.
- **CSRF protection middleware** — `stdlib/csrf.march`: `CSRF.generate_token()` (32 random bytes, base64-encoded via `random_bytes`/`base64_encode` builtins); `CSRF.token(conn)` — get session token from assigns; `CSRF.ensure_token(conn)` — idempotent token-assignment middleware; `CSRF.tag(conn)` — IOList hidden `<input>` for manual form building; `CSRF.tag_string(conn)` — String variant used by the `~H` desugar injection; `CSRF.validate(conn)` — parses `_csrf_token` from URL-encoded body and compares to session token; `CSRF.protect(conn)` — middleware that passes GET/HEAD/OPTIONS and JSON (`application/json`) requests through, validates token on POST/PUT/PATCH/DELETE, returns 403 on mismatch; `CSRF.skip(conn)` — marks conn to bypass CSRF (for webhooks). `~H` desugar pass (`lib/desugar/desugar.ml`): `csrf_form_close_pos` detects `<form method="post/put/patch/delete">` in string literals; `inject_csrf_tokens` splits the literal at the form's closing `>` and inserts `CSRF.tag_string(conn)` — providing automatic CSRF hidden-field injection for any `~H` template with a mutating form. 32 tests in `test/stdlib/test_csrf.march`.
- **Html template system** — `stdlib/html.march`: `Html.escape`, `Html.escape_attr`, `Html.raw`, `Html.safe_to_string`, `Html.tag(name, attrs, content)`, `Html.render_partial(fn, arg)`, `Html.render_collection(items, fn)`, `Html.layout(title, head_extra, body)`, `Html.content_hash(iol)`, `Html.list`, `Html.join`. `~H"..."` sigil desugars to `html_auto_escape(x)` per interpolation (instead of `Html.escape(to_string(x))`): `Html.Safe` values and IOList fragments embed without double-escaping. `IOList.hash(iol)` — FNV-1a 64-bit hash over segments without flattening; returns 16-char hex string for ETag generation. `IOList` is the canonical rendered HTML fragment type: cacheable in Vault, re-embeddable in `~H` sigils. 52 tests in `test/stdlib/test_html.march`, 19 tests in `test/stdlib/test_sigil.march`, 73 tests in `test/stdlib/test_iolist.march`. Example: `examples/templates.march` (full blog page: layout + nav + posts via partials/collections + ETag).
- **Bastion Islands library** (`islands/`) — `forge new islands --lib`. Island framework for WASM-hydrated UI components. `Islands` module: `HydrateOn` type (`Eager | Lazy | OnIdle | OnInteraction`); `Descriptor` type + registry (`empty_registry`, `register`, `find_island`, `registry_preload_hints`); server-side wrappers (`wrap`, `wrap_eager`, `client_only`); `bootstrap_script` + `preload_hint` for page `<head>`. `interface Island(s)` typeclass at module level. Client-side JS: `islands/runtime/march_islands.js` — actor-per-island (`IslandActor` class + cooperative `queueMicrotask` mailbox); hydration strategies (eager/DOMContentLoaded, lazy/IntersectionObserver, idle/requestIdleCallback, interaction/first-touch); event binding via `data-on-click/input/change/submit` attributes; cross-island messaging via `window.marchIslands.send(name, msg)`. WASM loading stub (`loadWasmModule`) with full Tier 4 integration documented for when browser target lands. 34 tests in `islands/test/islands_test.march`. Specs: `specs/bastion/architecture.md`, `specs/bastion/wasm-islands.md`, `specs/bastion/templates.md`.
- **Cross-file imports** — `import Message` (all public fns/types into scope unqualified, `UseAll`); `import Message.{StartupMessage, Query}` (selective dot-brace syntax, `UseNames`); `alias Message as Msg` (module alias, qualified access via `Msg.foo()`); `alias Message` (shorthand: last segment as alias). CamelCase→snake_case filename mapping (`HttpClient` → `http_client.march`). Cycle detection via in-progress Hashtbl during recursive loading. Missing-module errors with filename hint. Imported modules injected as `DMod` nodes before user decls so existing typecheck/eval `DUse`/`DAlias` machinery works unchanged. Resolved in `bin/main.ml` (`resolve_imports`). 3 new parse tests + 15-test March integration suite in `test/imports/`.
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
- **Event-loop HTTP server** — `runtime/march_http_evloop.c` (+ `march_http_io.c/h`, `march_http_internal.h`): kqueue (macOS/BSD) / epoll (Linux) event loop replacing the thread-per-connection model. Architecture: one event-loop thread per CPU core, each with its own SO_REUSEPORT listener fd and kqueue/epoll instance — zero cross-thread synchronization on the hot path. Non-blocking I/O infrastructure: `conn_state_t` per-connection state with inline 64 KB read buffer, `march_recv_nonblocking` / `march_send_nonblocking` state machines, per-thread free-list pool for connection objects. Edge-triggered events with accept batching. Compile-time switch: `-DMARCH_HTTP_USE_EVLOOP` (auto-detected by build system when `march_http_evloop.c` exists); thread-per-connection path retained as `MARCH_HTTP_USE_BLOCKING` fallback. Pipeline function called synchronously inline — no async/await needed. Plan: `specs/event_loop_plan.md`.
- **SIMD HTTP parser** — `runtime/march_http_parse_simd.c` (+ `.h`): SSE4.2 PCMPESTRI fast path processes 16 bytes/cycle to locate delimiters; `__attribute__((target("sse4.2")))` guards on all SIMD helpers; scalar fallback always compiled in (via `#if defined(__SSE4_2__)`). Clean C API: `march_http_parse_request_simd(buf, len, &req)` returns consumed byte count (>0), 0 for incomplete, -1 for error; `march_http_parse_pipelined` parses multiple pipelined requests from one buffer. `march_http.c` uses SIMD parser by default (feature-gated with `MARCH_HTTP_USE_SIMD`; disable with `-DMARCH_HTTP_DISABLE_SIMD`). 20 C tests in `test/test_http_simd.c` (GET/POST, pipelined ×3, malformed ×4, partial ×2, header whitespace, many headers, header limit, TechEmpower plaintext pattern). Compiles cleanly with `-msse4.2` on x86-64; ARM64 uses scalar path without warnings (`-Wno-unused-command-line-argument`).
- **Zero-copy response builder** — `runtime/march_http_response.c` (+ `.h`): pre-serialized status lines (200/201/204/301/302/304/400/401/403/404/405/500/503) stored as const globals; `march_response_t` struct with 160-entry fixed iovec array; `march_response_init/set_status/add_header/add_date_header/set_body/send` API builds responses with zero per-request malloc; `_Thread_local` 16 KB scratch buffer for dynamic parts (Content-Length digits, unknown status codes); double-buffered Date header cache (`"Date: ...\r\n"`) refreshed at most once/second via atomic fast-path + mutex slow-path; `march_response_send_plaintext(fd)` plaintext hot-path sends "Hello, World!" in 4 iovecs (static headers | cached Date | CRLF | body); `march_http_response_module_init()` called at server startup to pre-seed Date cache; `march_http.c` updated to include the header and call init. 20 C tests (76 checks) in `test/test_http_response.c`: init/reset, all static status lines, unknown-code scratch formatting, header iovec layout, Date cache freshness and thread-safety (8 threads × 1000 iters), full round-trips via `socketpair()` for 200/404/plaintext fast-path.
- **Atomic refcounting** — C11 atomics (`atomic_fetch_add/sub_explicit`) in `march_runtime.c`; RC thread-safe
- **Actor TIR lowering** — `lower_actor` in `lib/tir/lower.ml`; actors compile to native code via `ESpawn`/`ESend` lowering
- **Type-level natural number constraint solver (v1)** — `normalize_tnat` reduces concrete arithmetic (`2+3→5`, `(1+2)*3→9`) and identity/annihilation rules (`n+0→n`, `n*0→0`, `n*1→n`); `solve_nat_eq` in `unify` solves linear equations (`a+2=5 → a=3`, `a*k=n` when divisible); parser extended with `ty_nat_add`/`ty_nat_mul` levels and integer literals in type position; 9 tests in `type_level_nat` group
- **SRec recursive protocol unfolding** — `unfold_srec` in typecheck.ml; recursive session types handled; 6 new multi-turn tests (ping-pong loop, nested SRec, SChoose inside SRec, wrong type in loop)
- **Multi-party session types (MPST)** — `SMSend(role, T, S)` / `SMRecv(role, T, S)` role-annotated session type constructors; `project_steps` projects global choreography to each role's local type; MPST mergeability check for non-chooser roles in `ProtoChoice` (via `session_ty_exact_equal`); `MPST.new` creates N linear `TChan` endpoints (requires ≥3 roles); `MPST.send(ch, Role, v)` / `MPST.recv(ch, Role)` / `MPST.close(ch)` all type-checked at compile time; runtime pairwise queue routing (N*(N-1) directed queues shared between endpoints); 21 new tests (parsing, projection, type check ok/error, eval: 3-party auth, relay, 4-party chain, recv-before-send error)
- **Type error pretty-printing** — `pp_ty_pretty` wraps long type expressions at 60 chars with indented args; `report_mismatch` shows multi-line format for types >50 chars; `find_arg_mismatch` adds contextual notes identifying which arg/field differs
- **Forge build tool** — `forge/` package: `forge new/build/run/test/format/interactive/i/clean/deps`; scaffold generates valid March (PascalCase module names, `do/end` fn bodies, `println` builtin, test file with `main()`); 15 tests in `forge/test/test_forge.ml`
- **Borrow inference and elision (P7)** — `lib/tir/borrow.ml`: pre-Perceus optimistic fixpoint analysis. Infers which TCon/TString/TPtr function parameters are "borrowed" (only read via pattern match or field access, never stored/returned/passed to owning positions). Inter-procedural: params passed only to other borrowed positions remain borrowed. Integrated into `lib/tir/perceus.ml`: (a) call sites skip EIncRC for live borrowed args; (b) borrowed params added to the callee's `~borrowed` live-at-exit set, suppressing scrutinee EDecRC; (c) borrowed last-use args trigger caller-side EDecRC after the call instead of callee-side dec. HTTP Conn middleware pattern (multiple read-only middleware functions) generates zero RC ops for the Conn value. 10 new tests in `borrow_inference` group.
- **Optimization catalog + constant propagation** — `specs/optimizations.md`: comprehensive catalog of 12 implemented optimizations (fold, simplify, inline, DCE, escape analysis, stream fusion, TCO, Perceus, monomorphization, defun, unboxed LLVM types) and 4 planned (let-floating/join points, known-call, mutual TCO, representation polymorphism). `lib/tir/cprop.ml`: constant propagation pass substituting literal-bound variables at use sites, enabling cascading folds (e.g., `let x=3 in let y=x+4 in y` → `7` through CProp+Fold+DCE). Wired into `opt.ml` coordinator between Inline and Fold; `dune` updated. 6 new tests in `cprop` group.

- **Mutual TCO (P3) — shared loop with dispatch** — `lib/tir/llvm_emit.ml`: `tarjan_sccs` builds the tail-call adjacency graph and finds SCCs; `find_mutual_tco_groups` filters qualifying groups (SCC size ≥ 2, all cross-calls tail-calls, same return type); `emit_mutual_tco_group` emits one `@__mutco_f_g__` combined function per group with `mutual_loop` header, `switch` dispatch on an `i64` tag, back-edge `br` for all mutual tail calls, and thin wrapper functions preserving original names; `emit_module` processes groups before normal `emit_fn` iteration; `EApp` case in `emit_expr` intercepts mutual calls and redirects to back-edge. Runs in O(1) stack space for mutual tail-recursive groups of any size. 5 new `mutual_tco_codegen` IR-level tests (even/odd, three-way, state machine, non-tail guard, self-TCO unaffected). `bench/mutual_recursion.march` added.
- **Tail-Call Optimization (TCO) — loop transformation in LLVM IR** — `lib/tir/llvm_emit.ml` detects self-tail-recursive functions at codegen time (`has_self_tail_call` traversal), then transforms the emission: inserts a `tco_loop` header block, replaces tail self-calls with stores to parameter alloca slots + `br label %tco_loop` back-edge, and opens a dead block for any IR emitted by callers after the terminator. LLVM's mem2reg + DCE produce tight loop code. Guarantees O(1) stack space for tail-recursive functions at the compiled-code level. 4 new `tco_codegen` IR-level tests (factorial, fold, non-tail fib, countdown).

- **Mandatory tail-call enforcement (refined with structural recursion)** — after typechecking, every recursive function is statically checked to be either tail-recursive or structurally recursive. Tarjan's SCC detects mutual recursion; `check_tail_position` verifies each non-tail recursive call: if any argument is a pattern-bound sub-component of a parameter (e.g., `l`, `r` from `Node(l, r)`) or an arithmetic reduction (`n-1`, `n-2`), the call is allowed. Truly unbounded non-tail recursion (same argument, no reduction) still errors. Non-tail errors include function name, call-site span, wrapping context, and accumulator hint. All stdlib recursive functions rewritten with accumulators/path-stacks. 15 `tail_recursion` tests. Fixes fib, binary-trees, and tree-transform benchmarks.
- **DataFrame stdlib module (Phase 5/6 completion)** — Phase 5 joins confirmed fully implemented: `left_join`, `right_join`, `outer_join` with hash-join + nullable non-matching rows. Phase 6 new functions: `summarize(df)` (returns a stats-summary DataFrame; named `summarize` because `describe` is a reserved keyword), `sample(df, n)` (evenly-spaced row sampling), `train_test_split(df, ratio)` (Float ratio split → `(DataFrame, DataFrame)`), `col_add_float`, `col_mul_float`, `col_add_col` (element-wise arithmetic with Int→Float promotion). All public API functions now carry `doc "..."` strings with runnable examples. 47 comprehensive OCaml alcotest tests added in `test/test_march.ml` `stdlib_dataframe` group covering construction, LazyFrame, GroupBy, all 4 join kinds, stats, column arithmetic, and edge cases.
- **P9 — Columnar DataFrame Layout** — `VTypedArray of value array` in `lib/eval/eval.ml` with 10 builtins (`typed_array_create/get/set/length/slice/map/filter/fold/from_list/to_list`); `TypedArray(a)` type in typecheck. `stdlib/dataframe.march` Column variants (`IntCol`/`FloatCol`/`StrCol`/`BoolCol` + nullable variants) now store `TypedArray(X)` instead of `List(X)` for O(1) random access and cache-efficient column scans. Null bitmaps are `TypedArray(Bool)`. New `filter_col_by_mask` for single-pass boolean filtering. All column operations updated. Public API unchanged (`get_int_col` etc. still return `List`). 75/75 DataFrame tests pass.
- **DataFrame stdlib module (Phases 8–10)** — `stdlib/dataframe.march` extended with: (Phase 8) missing data: `drop_nulls`, `drop_nulls_in`, `fill_null`, `fill_null_df`, `fill_null_forward`, `fill_null_backward`; (Phase 9) window functions: `WindowExpr` ADT + `window(df, expr, out_col)` — `RowNum`, `Rank`, `DenseRank`, `RunningSum`, `RunningMean`, `Lag`, `Lead`; (Phase 10) reshape: `melt` (wide→long) and `pivot` (long→wide). 17 new tests (63 total in DataFrame test suite).
- **DataFrame stdlib module (Phase 7)** — `stdlib/dataframe.march`: columnar DataFrame with typed columns (`IntCol`, `FloatCol`, `StrCol`, `BoolCol`, `NullableIntCol`, `NullableFloatCol`, `NullableStrCol`, `NullableBoolCol`), row/column access, filtering via `ColExpr` DSL (now with `IsNull`/`IsNotNull` implemented), `LazyFrame`/`Plan` evaluation engine, `GroupBy`/aggregation (`Count`, `Sum`, `Mean`, `Min`, `Max`), `inner_join` + `left_join` + `right_join` + `outer_join` (hash-join, nullable columns for non-matching rows), CSV/JSON I/O, `col_describe`, `value_counts`, `col_is_nullable`, `col_null_count`, `col_to_nullable`. `eval_agg` uses `_safe` Stats variants so empty-group aggregation returns `NullVal` instead of panicking. Stats module: `mean_safe`, `variance_safe`, `std_dev_safe`, `min_safe`, `max_safe` (Result-returning). Benchmark: `bench/dataframe_bench.march`. 46 tests passing.
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
- **stdlib: Vault module** — `stdlib/vault.march`: ETS-like per-node in-memory KV store; `new`, `set`, `set_ttl` (per-key TTL, lazy expiry), `get`, `drop`, `update`, `size`, `get_or`, `has`; backed by `VVaultHandle` value variant + `vault_table`/`vault_row` OCaml types in `lib/eval/eval.ml`; 7 interpreter builtins; tables are global and shared across all actors without message passing; 10 tests passing.
- **`describe` keyword for test grouping** — `describe "name" do ... end` groups tests under a label with prefix propagation (e.g. `"auth login success"`); `DESCRIBE` lexer token; `DDescribe` AST node; fully wired through lexer, parser, desugar, typecheck, eval, TIR lower, formatter, and LSP analysis.
- **FFI interpreter dispatch** — `VForeign(lib, sym)` value type in `eval.ml`; `foreign_stubs` hashtable maps `(lib_name, symbol_name)` to OCaml stubs; `DExtern` in `eval_decl` binds extern functions to `VForeign` stubs; `apply_inner` dispatches `VForeign` via stub table; 25 math/libc stubs pre-registered (`sqrt`, `sin`, `cos`, `pow`, `atan2`, etc. across `"c"`/`"m"`/`"libm"` library names); `puts` stub registered; `declared_names` and `make_recursive_env` updated to include extern bindings.
- **Green thread scheduler (Phases 1-4)** — `runtime/march_scheduler.{h,c}`: Phase 1: ucontext_t stackful coroutines, mmap'd 64 KiB stacks with guard pages, FIFO run queue, reduction-based preemption (4000 budget). Phase 2: FIFO per-process mailboxes (`march_sched_send/recv/try_recv/wake`), PROC_WAITING state with spinlock-guarded recv-before-park protocol, process registry for O(1) PID lookup. Phase 3: M:N multi-thread with N per-thread schedulers, Chase-Lev work-stealing deques (`runtime/march_deque.h`), thread-local scheduler pointers, atomic status/PID/live-count fields, LCG random victim selection. Actor convergence: `march_runtime.c` actors run on green threads (recv→dispatch loop), `march_send` delegates to `march_sched_send`, old worker pool/Treiber stack/process_actor_turn removed. 11 C tests (4 Phase 1 + 4 Phase 2 + 3 Phase 3). **Phase 4** (compiled-code reduction counting): `_Thread_local int64_t march_tls_reductions` in scheduler, `march_yield_from_compiled()` resets budget and calls `march_sched_yield()`; `lib/tir/llvm_emit.ml` gains `is_leaf_callee` (builtins + `march_`-prefix C-runtime), `expr_has_call` (recursive TIR scan), `emit_reduction_check` (inline load/sub/store/icmp/br); `emit_fn` inserts check at entry for non-leaf non-TCO functions and at the `tco_loop` header for self-tail-recursive functions; `@march_tls_reductions` and `declare void @march_yield_from_compiled()` added to preamble. 4 new `phase4_reduction_codegen` IR tests (non-leaf check, all-leaf module, TCO loop check, non-recursive caller check).

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
- **Crypto builtins for PostgreSQL/SCRAM auth** — `sha256(String|Bytes)→String`, `hmac_sha256(key, msg)→Result(Bytes,String)`, `pbkdf2_sha256(password, salt, iterations, dklen)→Result(Bytes,String)`, `base64_encode(String|Bytes)→String`, `base64_decode(String)→Result(Bytes,String)`; all using Digestif 1.3.0; `tcp_recv_exact` and `md5` were already present; 12 new tests in `crypto builtins` group
- **49 C runtime builtins**: Float, math, string, list, file/dir functions
- **HTTP pipeline dispatch**: Closure-based invocation with refcount borrowing for thread safety

## Stdlib: File System (added 2026-03-20)
- [x] Path module — pure path manipulation (join, basename, dirname, extension, normalize)
- [x] Seq module — lazy church-encoded fold sequences (map, filter, take, drop, fold_while, etc.)
- [x] File module — Result-based I/O (read, write, append, delete, copy, rename, with_lines, with_chunks)
- [x] Dir module — directory operations (list, mkdir, mkdir_p, rmdir, rm_rf)
- [x] FileError ADT — NotFound, Permission, IsDirectory, NotEmpty, IoError
- [x] Step(a) type — Continue/Halt for fold_while early termination
