# March — TODO List

**Last updated:** 2026-03-22

This file tracks everything that still needs to get done. Organized by priority and category. Check `specs/progress.md` for what's already done.

---

## P0 — Blocking / Active

### Merge Pending Branches

- [ ] **Merge `claude/intelligent-austin` → main** — Standard Interfaces (Eq/Ord/Show/Hash) with `derive` syntax. Needs review; add tests in `test/test_march.ml` for derive expansion and eval dispatch.
- [ ] **Merge `claude/vibrant-bartik` → main** — LSP server (`march-lsp`). **Blocked on**: test suite (`lsp/test/test_lsp.ml`) must be written first. Tests being written on a separate rate-limited agent.

### Known Test Failures

- [ ] **Fix REPL JIT list literal** — 6 failing tests (`repl_jit_regression` 0,1,3,6,8 and `repl_jit_cross_line` 3). JIT compilation of `[1, 2, 3]` list literals broken; interpreter path fine. Root cause: codegen path in `repl_jit.ml` / `llvm_emit.ml` for list literals.

---

## P1 — High Impact / Near-Term

### Compiler: Pattern Matching

- [ ] **Exhaustiveness checking** — No compile-time analysis exists. Non-exhaustive patterns produce a runtime `Match_failure`. Need a pattern matrix usefulness/reachability algorithm (similar to OCaml's `lib/typing/parmatch.ml`). Should warn on non-exhaustive, error on unreachable arms. Implementation location: new pass in `lib/typecheck/typecheck.ml` or `lib/typecheck/exhaust.ml`.

### Compiler: Module System

- [ ] **Multi-level `use` paths** — `use A.B.*` currently unsupported; only `use A.*` works. Parser deferred this to avoid shift/reduce conflicts (`lib/parser/parser.mly`). Need to resolve grammar ambiguity and implement full path resolution in typecheck.
- [ ] **Opaque type enforcement** — `sig Name do type T end` declares `T` as abstract, but the type checker doesn't hide the representation. Callers can still access the internal structure. Need to enforce abstraction boundary in `typecheck.ml`.

### Compiler: Parser

- [ ] **Multi-error parser recovery** — Parser stops at first syntax error. Need to implement error recovery (e.g., Menhir's `error` token or a panic-mode resync strategy) to report multiple parse errors per file.

### Tooling: LSP Test Suite

- [ ] **Write `lsp/test/test_lsp.ml`** — Integration tests for the LSP server. Must cover:
  - Initialize → open file → receive diagnostics
  - Hover over a bound variable → get its type
  - Completion at a dot (module member access)
  - Go-to-definition for a function reference
  - Inlay hints on let bindings
  This is the merge blocker for `claude/vibrant-bartik`.

---

## P2 — Important / Near-Term

### REPL Quality

- [ ] **Clojure-level REPL quality** (stated goal) — The REPL should feel as good as Clojure's nREPL:
  - Persistent session state across JIT invocations (already partially there via RTLD_GLOBAL)
  - Better error recovery (don't drop session on typecheck error; keep env intact)
  - `:reload` command to re-eval a module
  - Tap/inspect tooling (like Clojure's `tap>`)
  - Pretty-printer for all value types (lists, records, ADTs)
- [ ] **REPL/compiler parity** — Features must work in both the interpreter REPL and the compiled path. List literals in JIT is the current gap. Any new feature added must be tested in both modes.

### Compiler: Type System

- [ ] **Type-qualified constructor names** — `build_ctor_info` in `lib/tir/llvm_emit.ml` uses a flat hashtable keyed by constructor name. Same-named constructors across different ADTs collide. Workaround: renamed stdlib constructors. Proper fix: type-qualify keys as `(type_name, ctor_name)`.
- [ ] **Actor handler return type checking** — Handlers should be statically verified to return the correct state record type. Currently type-checked but runtime exceptions still possible on mismatch.
- [ ] **Linear/affine propagation through record fields** — Fields declared `linear` in record definitions don't enforce field-level consumption. Record operations (update, projection) skip field linearity checks.

### Compiler: LLVM Codegen

- [ ] **Field-index map for records** — `EField`/`EUpdate` need a field→offset table from the type checker to emit correct GEP offsets beyond field 0. Currently only field 0 is correct.
- [ ] **Atomic refcounting** — Perceus RC ops are non-atomic. HTTP server works via explicit `inc_rc` borrowing for thread safety, but general multi-threaded code needs atomic RC or a GC to be safe. Options: atomic ops via C11 atomics in runtime, or switch to a tracing GC.
- [ ] **Actor TIR lowering** — Actor declarations are fully evaluated in the interpreter but dropped during TIR lowering. Compiling actor programs to native code requires implementing the lowering described in `specs/actor-lowering.md`.

---

## P3 — Medium-Term

### Language Features

- [ ] **MCP server for March** — An MCP (Model Context Protocol) server that exposes March's type checker and compiler as tools for LLM agents. Discussed as a post-LSP, pre-1.0 item. Would expose: typecheck a snippet, get type at position, search by type signature, expand typed holes.
- [ ] **Improve error messages for complex types** — Nested generics (`Map(String, List(Vec(Int, N)))`) produce very long error messages. Need: abbreviated type aliases in display, pretty-printer with line-wrapping.
- [ ] **Epoch-based capability revocation** — `send(cap, msg)` does not yet validate the epoch against a revocation list. Stubbed in Phase 1. Full implementation requires a revocation table and `(pid, epoch)` comparison in `eval.ml` / runtime C.
- [ ] **Supervisor restart policies** — Supervisors track restart history (`ai_restart_count`) but don't yet enforce policies (e.g., max 3 restarts in 5s → stop). See actor supervision section in `specs/features/actor-system.md`.
- [ ] **`SRec` recursive protocol unfolding** — Session type `SRec` (recursive protocol) is parsed and represented but not yet fully handled in the type checker's linear channel advancement logic.

### Testing

- [ ] **Actor compilation tests** — Test suite for actor programs compiled to native code (post actor-lowering).
- [ ] **Property tests for standard interfaces** — QCheck properties for Eq reflexivity/symmetry/transitivity, Ord total order, Show round-trip, Hash consistency (once `claude/intelligent-austin` is merged).
- [ ] **Fuzz testing for the parser** — AFL/libFuzzer on `lib/parser/parser.mly` to find crash-inducing inputs.

### Stdlib

- [ ] **`Set` module** — `Set(a)` type is declared in builtins but no stdlib implementation exists.
- [ ] **`BigInt` / `Decimal`** — Declared in type system design as stdlib numeric types; not yet implemented.
- [ ] **`Iterable` interface expansion** — `stdlib/iterable.march` is a placeholder (28 lines). Expand to full lazy iteration protocol (like Rust's `Iterator` or Haskell's `Foldable`).

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
- ✅ Standard Interfaces Eq/Ord/Show/Hash (on `claude/intelligent-austin`, pending merge)
- ✅ LSP server (on `claude/vibrant-bartik`, pending merge + tests)
