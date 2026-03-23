# March — TODO List

**Last updated:** 2026-03-23

This file tracks everything that still needs to get done. Organized by priority and category. Check `specs/progress.md` for what's already done.

---

## P0 — Blocking / Active

*(Nothing currently blocking.)*

---

## P1 — High Impact / Near-Term

### Tooling: LSP Feature Improvements

- [ ] **Implement 5 new LSP features** — Plan in `specs/plans/2026-03-23-lsp-feature-improvements.md`. Features:
  - Doc-string hover (show `--` comments above a function on hover)
  - Find references (`textDocument/references`)
  - Rename symbol (`textDocument/rename`)
  - Signature help (`textDocument/signatureHelp`)
  - Code actions: make-linear quickfix, pattern exhaustion quickfix

### Language: Application Entry Point

- [ ] **Implement `app` entry point** — `specs/application_spec.md` fully specifies the `app` declaration for long-lived supervised services (distinct from `main()` scripts). The parser, desugar, typecheck, and eval layers need to support it. Supervision spec is already in `specs/features/actor-system.md`.

---

## P2 — Important / Near-Term

### Compiler: Collections

- [ ] **HAMT implementation** — `specs/plans/hamt-proposal.md` describes replacing the AVL-tree `Map` module with a Hash Array Mapped Trie backed by the C runtime. Same HAMT engine would power `Map(k,v)`, `Set(a)`, and a future `PersistentVector(a)`. Depends on: `Hash` interface (already done). Current `Map` is AVL tree; HAMT gives O(log₃₂ n) ops and better cache behavior. See `stdlib/map.march` for the current implementation.

### Compiler: Type System

- [ ] **Epoch-based capability revocation** — `send(cap, msg)` does not yet validate the epoch against a revocation list. The `Cap(A, e)` type carries an epoch parameter but it is not checked at runtime in `eval.ml`. Stubbed in Phase 1. Full implementation requires a revocation table and `(pid, epoch)` comparison in `eval.ml` and the compiled runtime.

### REPL Quality

- [ ] **`tap>` async value inspector** — Clojure-style side-channel value tap: `tap> expr` registers value with a registered tap function without interrupting the pipeline. `:inspect/:i` covers synchronous inspection; `tap>` enables middleware-style observation in pipelines. Implementation: new builtin in `eval.ml` + `EBuiltin` in typecheck, wired to a REPL-registered callback.
- [ ] **REPL/compiler parity** — `:inspect` shows types but doesn't yet surface match exhaustiveness warnings inline. Any new language feature must be tested in both interpreter and JIT paths.

### Tooling

- [ ] **Forge build tool** — March-native package manager and build orchestrator. Uses the content-addressed store (CAS, `lib/cas/`) as its foundation. Should handle: `march.toml` manifest, dependency resolution via hash-pinned lockfile, `march build`, `march test`, `march run`, `march publish` (to a CAS-backed registry). Design goal: no version conflicts (multiple hash-pinned versions coexist), reproducible builds by default.

---

## P3 — Medium-Term

### Language Features

- [ ] **MCP server for March** — An MCP (Model Context Protocol) server that exposes March's type checker and compiler as tools for LLM agents. Post-LSP, pre-1.0. Would expose: typecheck a snippet, get type at position, search by type signature, expand typed holes.
- [ ] **Improve error messages for complex types** — Nested generics (`Map(String, List(Vec(Int, N)))`) produce very long error messages. Need: abbreviated type aliases in display, pretty-printer with line-wrapping. Implementation location: `lib/errors/errors.ml` + `lib/typecheck/typecheck.ml` pp_ty.
- [ ] **`SRec` full multi-turn testing** — `unfold_srec` is implemented in typecheck.ml but multi-turn recursive protocol usage (deeply nested `SRec`/`SVar` chains) needs more test coverage. Add tests for ping-pong-style looping protocols.
- [ ] **Supervisor restart policies: `rest_for_one`/`one_for_all`** — `max_restarts` enforcement is implemented. The `restart_policy` field (`one_for_one` only currently) should support `rest_for_one` (restart child and all children started after it) and `one_for_all` (restart all children on any failure), as specced in `specs/features/actor-system.md`.

### Testing

- [ ] **Actor compilation tests** — Test suite for actor programs compiled to native code (via `--compile`). Actor TIR lowering is implemented; there are no `dune runtest`-level tests verifying end-to-end actor compilation.
- [ ] **Cross-language benchmarks** — Benchmarks comparing March vs Go, Rust, OCaml on: actor throughput, HAMT ops, HTTP serving, recursive computation. Would validate that March's design goals (Perceus FBIP, zero-cost abstractions) are achieved in practice.

---

## P4 — Long-Term / Research

### Metatheory

- [ ] **Lean 4 mechanized metatheory** — Proof of type safety (progress + preservation) for the core March type system. Plan documented in `specs/lean4-metatheory-plan.md`. Requires: formalized grammar, operational semantics, type rules, mechanized proofs of canonical forms lemma, substitution lemma, and soundness theorem.

### Compiler Backend

- [ ] **Query-based/demand-driven compiler architecture** — Current pipeline is linear (parse → desugar → typecheck → eval/TIR). Design goal is a query-based architecture (like `rustc`'s `salsa`) for fine-grained incremental recompilation. Deferred post-v1.
- [ ] **Multi-party session types** — Binary session types are implemented (phases 1–3). Multi-party session types (MPST with choreographies) are deferred post-v1.
- [ ] **Constraint solver for type-level naturals** — Currently `TNat 1 + TNat 2` does not simplify to `TNat 3`. Full constraint solving for type-level arithmetic would enable richer dimension-checked types.
- [ ] **Row polymorphism** — Record operations on types with unknown record shapes. Would enable `e.field` when `e : TVar` to constrain the record shape rather than return a fresh var.

### Documentation

- [ ] **Language reference manual** — Comprehensive user-facing docs covering all syntax forms, built-in types, stdlib modules, and the compiler CLI. Currently only design specs and feature docs exist.
- [ ] **Tutorial / getting-started guide** — Walk through writing a first March program, compiling it, and using the REPL.

---

## Done (recently completed)

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
- ✅ **LSP test suite** — `lsp/test/test_lsp.ml` (826 lines, 55 tests); was the merge blocker for the LSP branch
- ✅ **REPL JIT list literal fix** — `[1, 2, 3]` now compiles correctly in JIT; all 812 tests pass (0 failures)
- ✅ **Exhaustiveness checking** — compile-time pattern matrix analysis in `lib/typecheck/typecheck.ml`; warns on non-exhaustive matches, errors on unreachable arms
- ✅ **Multi-level `use` paths** — `use A.B.*` / `use A.B.C` now fully supported; parser grammar ambiguity resolved, typecheck does full path resolution
- ✅ **Opaque type enforcement** — `sig Name do type T end` now hides representation; callers cannot access internal structure through the abstraction boundary
- ✅ **Multi-error parser recovery** — Menhir `error` token recovery; parser reports multiple syntax errors per file instead of stopping at the first
- ✅ **Clojure-level REPL quality** — `:reload` (re-eval last loaded file), `:inspect/:i <expr>` (type + value), pretty-printer with depth/collection truncation, error recovery (env preserved on typecheck error), REPL/compiler parity tests
- ✅ **Type-qualified constructor names** — `build_ctor_info` in `llvm_emit.ml` now keys by `(type_name, ctor_name)` pairs; same-named constructors across different ADTs no longer collide
- ✅ **Actor handler return type checking** — handlers statically verified to return the correct state record type; gap checks added in typecheck
- ✅ **Linear/affine propagation through record fields** — `EField` access on a linear record field consumes the field; `EUpdate` respects per-field linearity annotations
- ✅ **Field-index map for records** — `field_index_for` in `llvm_emit.ml` (line 762) computes correct GEP offsets for all fields; `EField`/`EUpdate` emit correct offsets beyond field 0
- ✅ **Atomic refcounting** — C11 atomics (`atomic_fetch_add_explicit`, `atomic_fetch_sub_explicit`) in `march_runtime.c`; RC operations are thread-safe
- ✅ **Actor TIR lowering** — `lower_actor` in `lib/tir/lower.ml` generates TIR type defs + dispatch functions for actor declarations; actors compile to native code
- ✅ **SRec recursive protocol unfolding** — `unfold_srec` in `lib/typecheck/typecheck.ml`; `SRec(x, body)` unfolded to concrete constructor before matching; recursive protocols handled in session type advancement
- ✅ **`Set` module** — `stdlib/set.march` (AVL tree-backed, full API)
- ✅ **`BigInt` / `Decimal`** — `stdlib/bigint.march`, `stdlib/decimal.march`; registered in `bin/main.ml` load order
- ✅ **`Iterable` interface expansion** — `stdlib/iterable.march` expanded from 28 lines to 184 lines with full lazy iteration protocol (map, filter, fold, take, drop, zip, enumerate, flat_map, any, all, find, count)
- ✅ **Property tests for Eq/Ord/Show/Hash** — QCheck2 properties for reflexivity/symmetry/transitivity, Ord total order, Show non-empty/distinct, Hash determinism/consistency
- ✅ **Fuzz testing for the parser** — 19 structural fuzz cases in `test_march.ml` (`parser_fuzz` group); covers deeply nested constructs, bad syntax with recovery, unicode, multi-error cases
- ✅ **Supervisor restart policies (max_restarts)** — `sc_max_restarts` + sliding time window enforced in `eval.ml`; supervisor crashes when child exceeds restart budget
- ✅ **Timsort, Introsort, AlphaDev sort** — `stdlib/sort.march` (615 lines)
- ✅ **Enum module** — `stdlib/enum.march` (314 lines)
