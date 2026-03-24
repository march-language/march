# March — TODO List

**Last updated:** 2026-03-24

This file tracks everything that still needs to get done. Organized by priority and category. Check `specs/progress.md` for what's already done.

---

## P0 — Blocking / Active

*(No active P0 blockers)*

---

## P1 — High Impact / Near-Term

### Tooling: Forge Build Tool

- ✅ **Implement `forge`** — Implemented as `forge/` package. Commands: `forge new`, `forge build`, `forge run`, `forge test`, `forge format`, `forge interactive`/`i`, `forge deps`, `forge clean`. Template scaffolding generates valid March code (PascalCase module names, `do/end` fn bodies, `println` builtin). 15 tests in `forge/test/test_forge.ml`.

---

## P2 — Important / Near-Term

### Compiler: Type System

- ✅ **Epoch-based capability revocation** — `revoke_cap(cap)` builtin, global `revocation_table`, `is_cap_valid(cap)`, and VCap handling in ESend. C runtime: `march_revoke_cap` / `march_is_cap_valid`. 5 new tests in supervision phase3 group.
- ✅ **Supervisor restart policies: `rest_for_one`/`one_for_all`** — Both policies fully implemented in `eval.ml` and tested (tests pass).
- ✅ **Improve error messages for complex types** — Added `pp_ty_pretty` (line-wrapping at 60 chars with indented args), `find_arg_mismatch` (identifies which arg differs), and enhanced `report_mismatch` with multi-line format for long types and contextual notes identifying the mismatching arg/field.

---

## P3 — Medium-Term

### Language Features

- [ ] **MCP server for March** — An MCP (Model Context Protocol) server that exposes March's type checker and compiler as tools for LLM agents. Post-LSP, pre-1.0. Would expose: typecheck a snippet, get type at position, search by type signature, expand typed holes.
- ✅ **Supervision tree spec V2** — `specs/features/actor-system.md` now has "Linear Types and Message Passing (V2 Design)" section documenting: why linear values must not be sent as messages, V2 rule (use `Send`/`Recv` session handles), current known soundness gap, and future path.
- ✅ **`SRec` full multi-turn testing** — 10 new tests: `srec_unfold_basic`, `srec_unfold_passthrough`, `srec_ping_pong_protocol`, `srec_ping_pong_unfold_one_step`, `srec_ping_pong_unfold_two_steps`, `srec_nested_srec`, `srec_finite_3_step`, `srec_choose_loop`, `srec_dual`, `srec_multi_turn_typechecks`.

### Testing

- ✅ **Actor compilation tests** — 8 new tests in `actor_compile` group: dispatch emitted, spawn fn emitted, handlers emitted, supervisor registers, monitor emitted, link emitted, multi-actor no crash, run_scheduler in main. All verify LLVM IR output of compiled actor programs.

---

## P4 — Long-Term / Research

### Metatheory

- [ ] **Lean 4 mechanized metatheory** — Proof of type safety (progress + preservation) for the core March type system. Plan documented in `specs/plans/lean4-metatheory-plan.md`. Requires: formalized grammar, operational semantics, type rules, mechanized proofs of canonical forms lemma, substitution lemma, and soundness theorem.

### Compiler Backend

- [ ] **Query-based/demand-driven compiler architecture** — Current pipeline is linear (parse → desugar → typecheck → eval/TIR). Design goal is a query-based architecture (like `rustc`'s `salsa`) for fine-grained incremental recompilation. Deferred post-v1.
- ✅ **Constraint solver for type-level naturals (v1)** — `normalize_tnat` reduces concrete arithmetic (`2+3 → 5`, `(1+2)*3 → 9`) and applies identity/annihilation laws (`n+0 → n`, `n*1 → n`, `n*0 → 0`). `solve_nat_eq` in `unify` solves linear equations (`a+2=5 → a=3`). Parser extended: `INT` as `TyNat`, `+`/`*` in type position via `ty_nat_add`/`ty_nat_mul` levels. 9 new tests in `type_level_nat` group.
- [ ] **Row polymorphism** — Record operations on types with unknown record shapes. Would enable `e.field` when `e : TVar` to constrain the record shape rather than return a fresh var.

### Documentation

- [ ] **Language reference manual** — Comprehensive user-facing docs covering all syntax forms, built-in types, stdlib modules, and the compiler CLI.
- [ ] **Tutorial / getting-started guide** — Walk through writing a first March program, compiling it, and using the REPL.

---

## Done (recently completed)

- ✅ **Built-in testing library** — `test "name" do...end` syntax as first-class language construct; `assert expr` with compiler-assisted failure messages (shows LHS/RHS values for binary comparisons); `setup do...end` (per-test hook) and `setup_all do...end` (once-before-all hook); `march test [--verbose] [--filter=pattern] [files...]` subcommand; dot output by default, `--verbose` for full names; `forge test` delegates to `march test`. AST: `DTest`/`DSetup`/`DSetupAll`/`EAssert`; fully wired through lexer, parser, desugar, typecheck, eval, TIR lower, formatter, LSP analysis. 13 new tests in `testing_library` group.
- ✅ **stdlib: Bytes, Process, Logger, Actor, Flow modules** — 5 new stdlib modules + docs:
  - `stdlib/bytes.march`: Raw byte buffer (`Bytes` type wrapping `List(Int)`), `from_string`/`to_string`, `from_list`/`to_list`, `get`, `slice`, `concat`, `to_hex`, `encode_base64`/`decode_base64` (pure arithmetic, no bitwise ops), `encode_utf8`/`decode_utf8`. Self-contained with inline helpers.
  - `stdlib/process.march`: OS subprocess interaction — `Process.run/run_stream` (sync/streaming), `env/set_env`, `cwd`, `argv`, `pid`, `exit`; `ProcessResult` type with `exit_code/stdout/stderr/ok` accessors.
  - `stdlib/logger.march`: Structured logging — `Logger.Level = Debug | Info | Warn | Error`; `set_level`/`get_level`; `with_context`/`clear_context`; `debug/info/warn/error/log/log_with`; OCaml global state in `eval.ml`.
  - `stdlib/actor.march`: Actor messaging helpers — `Actor.cast(pid, msg)` (fire-and-forget), `Actor.call(pid, msg, timeout)` (sync, wraps in `Call(ref_id, msg)`, returns `Ok(result)` or `Err(reason)`), `Actor.reply(ref, result)`.
  - `stdlib/flow.march`: Backpressure pipeline abstraction — `Stage(a)` wrapping `Seq(a)`; producers: `from_list/from_seq/unfold/range`; transformers: `map/filter/flat_map/take/drop/batch/with_concurrency`; consumers: `collect/run/reduce/into/each/count/find/any/all`. `with_concurrency` is a no-op in interpreter (hint for compiled runtime). `stdlib/docs/flow.md` documents design, examples, GenStage comparison.
  - OCaml builtins added to `eval.ml`: `byte_to_char`, `process_spawn_sync/lines`, `process_env/set_env/cwd/exit/argv/pid`, `logger_*` (6 ops), `actor_cast/call/reply` + `pending_replies` hashtable + `next_call_ref`.
  - 28 new tests across `bytes`, `logger`, `flow`, `actor_module` groups.

- ✅ **`app` entry point (Phase 1 interpreter)** — `APP`/`ON_START`/`ON_STOP` lexer tokens; `DApp` AST node; `app_decl` parser rule; desugar converts `DApp` → `__app_init__` function with `SupervisorSpec` return type annotation; mutual-exclusivity check; `spawn_from_spec`; SIGTERM/SIGINT handlers; graceful shutdown; process registry (`whereis`/`whereis_bang`); dynamic supervisors; named children; `on_start`/`on_stop` lifecycle hooks. 45 tests across 6 groups.
- ✅ **HAMT engine for Map/Set + persistent Array** — `stdlib/hamt.march` (generic 32-way HAMT engine); `stdlib/map.march` rewritten with HAMT; `stdlib/set.march` rewritten with HAMT; `stdlib/array.march` added (persistent vector, 32-way trie + tail buffer, O(1) amortized push/pop). 26 new tests.
- ✅ **`tap>` async value inspector** — Clojure `tap>` model: `tap` builtin (∀a. a → a) sends values to a thread-safe global tap bus (Mutex + Queue in `eval.ml`); REPL drains after each expression and displays tapped values in orange in TUI pane and as `tap> value` in simple mode. Type registered in typecheck `base_env`. 6 tests in `tap` group.
- ✅ **Constraint solver for type-level naturals (v1)** — `normalize_tnat` reduces concrete arithmetic and identity/annihilation laws; `solve_nat_eq` solves linear equations (e.g. `a+2=5 → a=3`); parser extended with `ty_nat_add`/`ty_nat_mul` levels and `INT` as `TyNat`; 9 tests in `type_level_nat` group.
- ✅ **REPL/compiler parity enforcement** — Added `check_parity` helper that runs March expressions through both interpreter (`repl_eval_exprs`) and JIT (`run_expr`) and asserts identical output. New `repl_compiler_parity` test group with 5 tests (basic arith, bool ops, string interp, closures, if/else). JIT tests skip gracefully when clang is unavailable. Approach documented inline.
- ✅ **Cross-language benchmarks** — `bench/elixir/`, `bench/ocaml/`, `bench/rust/` contain idiomatic implementations of fib(40), binary-trees(15), tree-transform(depth=20×100), and list-ops(1M). `bench/run_benchmarks.sh` compiles all four languages and reports median/min/max over 10 runs. Results in `bench/RESULTS.md`: FBIP delivers 7.5–19× speedup over OCaml/Rust on tree-transform; March ties Rust on fib; OCaml wins binary-trees (generational GC); Rust wins list-ops (iterator fusion).
- ✅ **Mandatory tail-call enforcement (refined)** — after typechecking, every recursive function is statically verified to be either tail-recursive OR structurally recursive. Tarjan's SCC detects mutual recursion groups; `check_tail_position` verifies each non-tail recursive call is structurally recursive: either all arguments are pattern-bound sub-components of a parameter (e.g., `l`, `r` from `Node(l, r)`) or arithmetic reductions of a parameter (e.g., `n-1`, `n-2`). Truly unbounded non-tail recursion (same argument, no reduction) still errors. Fixes fib, binary-trees, and tree-transform benchmarks. 15 `tail_recursion` tests (5 new structural tests added).
- ✅ **Multi-party session types (MPST)** — `SMSend(role, T, S)` / `SMRecv(role, T, S)` role-annotated session type constructors; `project_steps` projects global choreography to each role's local type; MPST mergeability check for non-chooser roles in `ProtoChoice`; `MPST.new`/`MPST.send`/`MPST.recv`/`MPST.close` all type-checked at compile time; runtime pairwise queue routing (N*(N-1) directed queues); 21 new tests.
- ✅ **REPL JIT permanent fix** — `partition_fns` in `lib/jit/repl_jit.ml` was eagerly marking functions compiled BEFORE `compile_fragment` succeeded, poisoning `compiled_fns` on any failure. Fixed by making `partition_fns` pure and adding `mark_compiled_fns` called only after successful dlopen. Regression tests: `test_repl_jit_stdlib_reverse`, `test_repl_jit_stdlib_no_precompile`, `test_repl_jit_stdlib_length_3x`.
- ✅ **5 new LSP features** — Doc-string hover, find references (`textDocument/references`), rename symbol (`textDocument/rename`), signature help (`textDocument/signatureHelp`), code actions (make-linear quickfix, pattern exhaustion quickfix). 27 new tests; 84 total LSP tests.
- ✅ **Epoch-based capability revocation** — `revoke_cap(cap)` + revocation table; VCap handling in ESend; C runtime `march_revoke_cap`/`march_is_cap_valid`; 5 new supervision phase3 tests
- ✅ **Supervisor restart policies** — `one_for_one`, `one_for_all`, `rest_for_one` all implemented and tested in eval.ml
- ✅ **Actor compilation tests** — 8 tests in `actor_compile` group verifying LLVM IR output for actor programs (dispatch, spawn, handlers, supervisor, monitor, link)
- ✅ **SRec multi-turn testing** — 10 new tests: unfold, ping-pong (1+2 steps), nested SRec, finite protocol, choose-loop, dual, typecheck
- ✅ **Supervision tree spec V2** — `specs/features/actor-system.md` documents linear type restrictions, V2 transfer protocol via session types, and future path
- ✅ **Stream fusion / deforestation** — `lib/tir/fusion.ml` TIR optimization pass; fuses `map+fold`, `filter+fold`, `map+filter+fold` chains into single-pass fused functions with no intermediate lists; ANF flatten step hoists lambda pre-bindings; guards for multi-use and impure ops; wired into pipeline after mono, before defun (`--opt` flag); 9 tests
- ✅ Match syntax changed to `match expr do | pat -> body end` (was `with`)
- ✅ String interpolation `${}` in lexer + desugar
- ✅ `march fmt` code formatter
- ✅ 36 QCheck2 property-based tests
- ✅ Interpreter/compiler oracle tests
- ✅ Perceus RC analysis + FBIP optimization
- ✅ CAS build cache (BLAKE3, 2-tier project/global)
- ✅ TIR pipeline: lower → mono → defun → perceus → escape → opt → LLVM
- ✅ Actor system: spawn/send/kill/monitor/link/supervise (interpreter)
- ✅ Session types (binary, phases 1–3)
- ✅ Time-travel debugger
- ✅ Full TUI REPL with JIT
- ✅ HTTP/WebSocket stdlib + C runtime
- ✅ Zed editor extension (Tree-sitter grammar)
- ✅ **Standard Interfaces Eq/Ord/Show/Hash** — merged from `claude/intelligent-austin`; `derive` syntax, eval dispatch for `==`/`show`/`hash`/`compare`, 18 tests
- ✅ **LSP server** (`march-lsp`) — merged from `claude/vibrant-bartik`; diagnostics, hover, goto-def, completion, inlay hints, semantic tokens, actor info; Zed extension wired up
- ✅ **LSP test suite** — `lsp/test/test_lsp.ml` (84 tests); was the merge blocker for the LSP branch; expanded with 27 new tests for doc strings, find-refs, rename, sig-help, code actions
- ✅ **REPL JIT list literal fix** — `[1, 2, 3]` now compiles correctly in JIT; all 812 tests pass (0 failures)
- ✅ **Exhaustiveness checking** — compile-time pattern matrix analysis in `lib/typecheck/typecheck.ml`; warns on non-exhaustive matches, errors on unreachable arms
- ✅ **Multi-level `use` paths** — `use A.B.*` / `use A.B.{f,g}` now fully supported; `use_path_tail` in parser, qualified lookups in typecheck
- ✅ **Opaque type enforcement** — `sig Name do type T end` now hides representation; callers cannot access internal structure through the abstraction boundary
- ✅ **Multi-error parser recovery** — `Parse_errors` module collects errors without stopping; multiple syntax errors per file reported
- ✅ **Clojure-level REPL quality** — `:reload` (re-eval last loaded file), `:inspect/:i <expr>` (type + value), pretty-printer with depth/collection truncation, error recovery (env preserved on typecheck error), REPL/compiler parity tests
- ✅ **Type-qualified constructor names** — `build_ctor_info` in `llvm_emit.ml` now keys by `(type_name, ctor_name)` pairs; same-named constructors across different ADTs no longer collide
- ✅ **Actor handler return type checking** — handlers statically verified to return the correct state record type; gap checks added in typecheck
- ✅ **Linear/affine propagation through record fields** — `EField` access on a linear record field consumes the field; `EUpdate` respects per-field linearity annotations
- ✅ **Field-index map for records** — `field_index_for` in `llvm_emit.ml` (line 762) computes correct GEP offsets for all fields; `EField`/`EUpdate` emit correct offsets beyond field 0
- ✅ **Atomic refcounting** — C11 atomics (`atomic_fetch_add_explicit`, `atomic_fetch_sub_explicit`) in `march_runtime.c`; RC operations are thread-safe
- ✅ **Actor TIR lowering** — `lower_actor` in `lib/tir/lower.ml` generates TIR type defs + dispatch functions for actor declarations; actors compile to native code
- ✅ **SRec recursive protocol unfolding** — `unfold_srec` in `lib/typecheck/typecheck.ml`; `SRec(x, body)` unfolded to concrete constructor before matching; recursive protocols handled in session type advancement
- ✅ **`Set` module** — `stdlib/set.march` (289 lines, AVL tree-backed, full API)
- ✅ **`BigInt` / `Decimal`** — `stdlib/bigint.march` (470 lines), `stdlib/decimal.march` (277 lines); registered in `bin/main.ml` load order
- ✅ **`Iterable` interface expansion** — `stdlib/iterable.march` expanded to 184 lines with full lazy iteration protocol (map, filter, fold, take, drop, zip, enumerate, flat_map, any, all, find, count)
- ✅ **Property tests for Eq/Ord/Show/Hash** — QCheck2 properties for reflexivity/symmetry/transitivity, Ord total order, Show non-empty/distinct, Hash determinism/consistency
- ✅ **Fuzz testing for the parser** — 19 structural fuzz cases in `test_march.ml` (`parser_fuzz` group); covers deeply nested constructs, bad syntax with recovery, unicode, multi-error cases
- ✅ **Supervisor restart policies (max_restarts)** — `sc_max_restarts` + sliding time window enforced in `eval.ml`; supervisor crashes when child exceeds restart budget
- ✅ **Module `alias` declarations** — `alias Long.Name, as: Short` syntax and qualified name resolution in typecheck
- ✅ **Timsort, Introsort, AlphaDev sort** — `stdlib/sort.march` (615 lines)
- ✅ **Enum module** — `stdlib/enum.march` (314 lines)
- ✅ **March-native stdlib test suite** — 23 `.march` test files in `test/stdlib/` covering all stdlib modules; `stdlib/test.march` (Test module with assert_true/false/eq_int/eq_str/some/none/ok/err); `test/test_stdlib_march.ml` OCaml runner (7 suites: Http, HttpTransport, HttpClient, HttpServer, WebSocket, Process, Logger)
- ✅ **Logger module additions** — `Logger.level_from_string`, `level_rank`, `level_enabled`, `format_entry`, `log_if` added to `stdlib/logger.march`
- ✅ **TCE structural recursion warning** — `check_tail_position` in `typecheck.ml` now emits a Warning when a structurally-recursive (but non-tail) call is detected; distinguishes arithmetic reductions (`n-1`) from pattern-bound sub-components
- ✅ **stdlib: Random module** — `stdlib/random.march`: purely-functional pseudorandom number generation using xoshiro256** algorithm; `Rng` state record; `seed/next_int/next_float/next_bool/next_range/shuffle`; all functions pure (take Rng, return `(value, Rng)`); no global mutable state; registered in `bin/main.ml` stdlib load order.
- ✅ **stdlib: Stats module** — `stdlib/stats.march`: descriptive statistics over `List(Float)`; `mean/variance/std_dev/median/mode/min/max/range/percentile/covariance/pearson_correlation`; pure functional, no external dependencies; registered in `bin/main.ml`.
- ✅ **stdlib: Plot module** — `stdlib/plot.march`: SVG chart generation; `Color`/`Style`/`Series`/`Chart` types; `line_series/scatter_series/bar_series/histogram_series`; `new/add_series/set_title/set_size/set_padding/to_svg`; self-contained pure string building, no external dependencies; registered in `bin/main.ml`.
- ✅ **`describe` keyword for test grouping** — `describe "name" do ... end` syntax groups tests under a label; `DESCRIBE` lexer token; `DDescribe` AST node; desugared recursively; typechecked as Unit; `collect_test_decls` flattens describe groups with prefixed names (e.g. `"auth login success"`); fully wired through all compiler passes (lexer, parser, AST, desugar, typecheck, eval, TIR lower, formatter, LSP analysis).
- ✅ **FFI interpreter dispatch (`extern` blocks)** — `VForeign(lib, sym)` value; `foreign_stubs` hashtable in `eval.ml` mapping `(lib_name, symbol_name)` to OCaml stubs; `DExtern` in `eval_decl` binds each extern function to a `VForeign` stub; `apply_inner` dispatches `VForeign` via the stub table; pre-registered: 25 math functions (`sqrt`, `sin`, `cos`, `pow`, etc.), `puts`; `declared_names`/`make_recursive_env` updated to include extern bindings.
- ✅ **New March-native stdlib test files** — `test/stdlib/test_random.march`, `test_stats.march`, `test_plot.march`, `test_bigint.march`, `test_decimal.march`, `test_enum.march`, `test_math.march`, `test_queue.march`, `test_string.march` added.
