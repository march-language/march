# Optimization — Implementation Plan

## Current State

### What Exists

**TIR Optimizer** (`lib/tir/opt.ml`):
- Coordinator that runs four passes in a fixed-point loop (max 5 iterations):
  1. `Inline` (`lib/tir/inline.ml`) — inlines small, pure functions
  2. `Fold` (`lib/tir/fold.ml`) — constant folding for arithmetic
  3. `Simplify` (`lib/tir/simplify.ml`) — peephole optimizations
  4. `Dce` (`lib/tir/dce.ml`) — dead code elimination
- `Purity` oracle (`lib/tir/purity.ml`) — conservatively identifies side-effect-free expressions
- Passes are functional transformations on TIR modules
- Opt passes integrate into the pipeline between Perceus/Escape and LLVM emit

**CLI flags** (`bin/main.ml`):
- `--no-opt` — skip optimization passes entirely
- `--fast-math` — emit LLVM fast-math flags
- `--opt N` — clang optimization level (0–3)

**LLVM-level optimization**:
- Passes clang's `-O` flag through to LLVM's optimization pipeline
- No custom LLVM passes; relies entirely on clang's default pass pipeline

**JIT** (`lib/jit/jit.ml`, `lib/jit/repl_jit.ml`):
- `jit.ml` provides OCaml FFI stubs for `dlopen`/`dlsym`/`dlclose` plus call stubs:
  - `call_void_to_ptr`, `call_void_to_void`, `call_void_to_int`, `call_void_to_float`, `call_ptr_to_ptr`
- `repl_jit.ml` implements compile-and-dlopen REPL:
  - Each REPL input → LLVM IR → `clang -shared -fPIC` → `.so` → `dlopen` → call via function pointer
  - Tracks compiled functions to avoid recompilation
  - Maintains global variable list across fragments

### What's Missing

**Math optimizations** — Per `2026-03-19-math-optimization-plan.md`, six optimization modules were designed but the current implementations are basic stubs or minimal:
- `fold.ml` handles simple constant folding but not algebraic simplification
- No strength reduction (e.g., `x * 2` → `x + x`)
- No loop-invariant code motion
- No common subexpression elimination

**JIT compilation** — The current JIT is "compile to .so and dlopen", not a true JIT:
- Full clang invocation per REPL input (~100ms+ per expression)
- No in-memory compilation
- No hot-path optimization or profile-guided compilation
- Cross-fragment function calls not supported (known limitation)

**Additional LLVM passes** — No custom LLVM passes; March-specific optimizations happen only at TIR level.

**Profile-guided optimization (PGO)** — No profiling infrastructure; no feedback-directed optimization.

---

## Target State (from specs)

Per `2026-03-19-math-optimization-plan.md` and `specs/design.md`:

1. **Rich TIR optimization**: Constant folding, algebraic simplification, strength reduction, inlining with heuristics, dead code elimination, common subexpression elimination
2. **LLVM pass customization**: Custom LLVM passes for March-specific patterns (RC operation coalescing, arena allocation optimization)
3. **JIT with in-memory compilation**: Use LLVM's MCJIT or ORC JIT for in-process compilation without disk round-trips
4. **Profile-guided optimization**: Instrumented builds → profile data → optimized rebuild
5. **Math-specific optimizations**: `--fast-math` mode with algebraic reassociation, FMA generation, reciprocal approximation

---

## Implementation Steps

### Phase 1: TIR Optimization Enrichment (Medium complexity, Low risk)

**Step 1.1: Algebraic simplification in fold.ml**
- File: `lib/tir/fold.ml`
- Add rules:
  - `x + 0` → `x`, `x * 1` → `x`, `x * 0` → `0`
  - `x - x` → `0`, `x / x` → `1` (guard: x ≠ 0)
  - `x * 2` → `x + x` (strength reduction)
  - `!!x` → `x` (double negation)
  - `x && true` → `x`, `x || false` → `x`
  - `if true then a else b` → `a`
- Guard all folding with purity oracle (don't fold if x has side effects)
- Estimated effort: 2 days

**Step 1.2: Constant propagation**
- File: `lib/tir/fold.ml` or new `lib/tir/constprop.ml`
- Track `let x = <constant>` bindings in a map
- Replace subsequent uses of `x` with the constant
- Propagate through `let` chains: `let x = 5; let y = x + 3` → `let y = 8`
- Estimated effort: 3 days
- Risk: Must respect control flow — don't propagate into branches where the binding might not dominate

**Step 1.3: Common subexpression elimination (CSE)**
- File: new `lib/tir/cse.ml`
- Hash each pure expression; if the same hash appears twice with the same inputs, replace the second with a reference to the first
- Only apply to pure expressions (via purity oracle)
- Add to optimizer's pass list in `opt.ml`
- Estimated effort: 3 days

**Step 1.4: Improve inlining heuristics**
- File: `lib/tir/inline.ml`
- Current heuristic: inline if function is small. Improve to consider:
  - Call frequency (inline hot functions more aggressively)
  - Constant arguments (inlining enables further constant folding)
  - Single-call-site functions (always inline — eliminates the function entirely)
  - Recursive functions (never inline, or inline one level with depth limit)
- Estimated effort: 2 days

**Step 1.5: Loop optimizations**
- File: new `lib/tir/loop_opt.ml`
- Detect tail-recursive functions (already done for TCO in codegen, but expose for optimization)
- Loop-invariant code motion: move pure expressions out of recursive calls
- Note: March uses recursive functions, not explicit loops; "loop" optimizations apply to tail-call patterns
- Estimated effort: 4 days
- Risk: Requires dominator analysis in recursive call graphs

### Phase 2: RC Operation Optimization (Medium complexity, Medium risk)

**Step 2.1: RC operation coalescing**
- File: `lib/tir/perceus.ml` or new `lib/tir/rc_opt.ml`
- After Perceus inserts RC operations, coalesce adjacent inc/dec on the same object:
  - `incrc(x); incrc(x)` → `incrc(x, 2)` (batched increment)
  - `incrc(x); decrc(x)` → no-op (already handled by Perceus Phase 3, but catch more cases)
- Estimated effort: 2 days

**Step 2.2: RC sinking**
- File: `lib/tir/rc_opt.ml`
- Move `decrc` operations as late as possible (just before the object becomes unreachable)
- Move `incrc` operations as early as possible (just after the reference is created)
- This reduces the window where RC operations might contend in multi-threaded code
- Estimated effort: 3 days
- Risk: Must maintain correctness — sinking decrc past a potential use is a use-after-free

**Step 2.3: Elide RC for short-lived temporaries**
- File: `lib/tir/rc_opt.ml`
- If an object is created, used once, and immediately freed, skip RC entirely:
  - `let x = alloc(...); use(x); free(x)` → `let x = stack_alloc(...); use(x)` (if escape analysis agrees)
- This extends escape analysis to patterns Perceus doesn't catch
- Estimated effort: 2 days

### Phase 3: LLVM Pass Customization (Medium complexity, Medium risk)

**Step 3.1: Emit LLVM metadata for March-specific patterns**
- File: `lib/tir/llvm_emit.ml`
- Add LLVM metadata annotations:
  - `!march.rc` on RC operations (so custom passes can identify them)
  - `!march.pure` on functions known to be pure
  - `!march.arena` on arena-allocated objects
- Estimated effort: 2 days

**Step 3.2: Custom LLVM pass for RC coalescing at IR level**
- New file or integration into clang plugin
- Identify adjacent `call @march_incrc` / `call @march_decrc` in LLVM IR
- Coalesce or eliminate redundant pairs that the TIR-level optimizer missed
- Estimated effort: 5 days
- Risk: Writing LLVM passes requires LLVM C++ API knowledge; consider using the new pass manager

**Step 3.3: Vectorization hints**
- File: `lib/tir/llvm_emit.ml`
- For numeric array operations, emit LLVM vectorization hints
- `!llvm.loop.vectorize.enable` metadata on inner loops
- Estimated effort: 2 days
- Dependency: Requires array/vector types in the language (currently lists are linked)

### Phase 4: JIT Compilation (High complexity, High risk)

**Step 4.1: Evaluate JIT backends**
- Research: Compare LLVM ORC JIT, LLVM MCJIT, and copy-and-patch JIT
- ORC JIT: Most flexible, supports lazy compilation, but complex API
- MCJIT: Simpler but deprecated in favor of ORC
- Copy-and-patch: Very fast compilation, limited optimization, used by CPython 3.13
- Estimated effort: 2 days (research), 1 day (decision)

**Step 4.2: In-memory LLVM compilation for REPL**
- Files: `lib/jit/jit.ml`, `lib/jit/repl_jit.ml`
- Replace `clang -shared` → dlopen pipeline with in-memory compilation:
  - Generate LLVM IR (already done)
  - Use LLVM C API (via OCaml bindings) to compile IR to machine code in memory
  - Get function pointer directly from JIT engine
- Estimated effort: 10 days
- Risk: OCaml LLVM bindings may not expose ORC JIT API; may need custom C stubs
- Dependency: Need `llvm` opam package or custom bindings

**Step 4.3: Cross-fragment symbol resolution**
- File: `lib/jit/repl_jit.ml`
- Current limitation: functions defined in one REPL fragment can't call functions from another
- With ORC JIT: use a shared symbol table across JIT compilation units
- Each new fragment's unresolved symbols are looked up in prior fragments' symbol tables
- Estimated effort: 5 days

**Step 4.4: Tiered compilation**
- File: `lib/jit/repl_jit.ml`
- Tier 0: Interpret (current tree-walker for immediate feedback)
- Tier 1: Quick compile (minimal optimization, fast code generation)
- Tier 2: Optimized compile (full TIR optimization + LLVM -O2)
- Promote from Tier 0 → Tier 1 after N invocations; Tier 1 → Tier 2 after M invocations
- Estimated effort: 8 days
- Dependency: Steps 4.2, 4.3

### Phase 5: Profile-Guided Optimization (Low complexity, Low risk — but deferred)

**Step 5.1: Instrumented build mode**
- File: `bin/main.ml`, `lib/tir/llvm_emit.ml`
- `march build --profile` emits instrumented code that counts function call frequencies and branch taken/not-taken ratios
- Store profile data in `.march/profile/`
- Estimated effort: 3 days

**Step 5.2: Profile-guided inlining**
- File: `lib/tir/inline.ml`
- Read profile data; inline functions called >N times from a given call site
- Estimated effort: 2 days

**Step 5.3: Profile-guided LLVM optimization**
- Pass clang's `-fprofile-use` flag with collected profile data
- Estimated effort: 1 day

---

## Dependencies

```
Phase 1 (TIR enrichment) ← no blockers
Phase 2 (RC optimization) ← no blockers (but benefits from Phase 1)
Phase 3 (LLVM passes) ← benefits from Phase 1 and Phase 2

Phase 4 (JIT) ← independent of Phases 1-3; depends on LLVM bindings
Phase 5 (PGO) ← depends on Phases 1, 4 for maximum benefit

Cross-plan dependencies:
- Phase 2 interacts with concurrency-plan.md Phase 3 (atomic RC)
- Phase 4 interacts with concurrency-plan.md Phase 3 Step 3.4 (yield points in compiled code)
```

## Testing Strategy

### TIR Optimization
1. **Correctness**: Optimized program produces same output as unoptimized
2. **Fold tests**: `5 + 3` → `8`; `x * 0` → `0`; `if true then a else b` → `a`
3. **CSE tests**: `let a = f(x); let b = f(x)` → `let a = f(x); let b = a` (when f is pure)
4. **Inline tests**: Single-call-site function inlined; recursive function not inlined
5. **Performance**: Benchmark suite (fib, binary_trees, list_ops) shows measurable improvement
6. **Fixed-point**: Optimizer converges within 5 iterations on all test cases

### RC Optimization
1. **No leaks**: Run with valgrind/ASAN; no memory leaks after RC optimization
2. **No use-after-free**: Stress test with ASAN; RC sinking doesn't create dangling references
3. **Coalescing**: Inspect LLVM IR; adjacent inc/dec pairs eliminated

### JIT
1. **REPL correctness**: All existing REPL test cases pass with new JIT backend
2. **Cross-fragment calls**: Define function in fragment 1, call in fragment 2 — works
3. **Performance**: REPL response time < 10ms for simple expressions (vs ~100ms with clang)
4. **Tiered compilation**: Function starts interpreted, gets compiled after N calls; output identical

## Open Questions

1. **LLVM bindings**: Does the OCaml `llvm` opam package support ORC JIT? If not, do we write custom C stubs or use a different JIT approach?

2. **Copy-and-patch vs. LLVM JIT**: Copy-and-patch JIT (à la CPython 3.13) is much simpler and faster to compile, but produces worse code. Is the REPL latency improvement worth the code quality tradeoff?

3. **Whole-program optimization**: Monomorphization is whole-program. Can we run TIR optimizations before monomorphization (on polymorphic code) or only after? Before is more efficient (optimize once, specialize many); after is simpler (concrete types enable more folding).

4. **SIMD/vectorization**: March doesn't have array types (only linked lists). Should we add arrays to enable vectorization? Or rely on the optimizer converting list operations to array operations when possible?

5. **Tail call optimization**: TCO is critical for functional languages. Does LLVM's `musttail` work reliably on all platforms? Are there cases where March's TCO detection in the TIR doesn't match LLVM's requirements?

6. **Optimization observability**: Should the compiler have a `--dump-opt-stats` flag showing what each optimization pass did? Useful for tuning heuristics.

## Estimated Total Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1: TIR enrichment | 14 days | Low |
| Phase 2: RC optimization | 7 days | Medium |
| Phase 3: LLVM passes | 9 days | Medium |
| Phase 4: JIT | 25–26 days | High |
| Phase 5: PGO | 6 days | Low (deferred) |
| **Total** | **61–62 days** | |

## Suggested Priority

1. **Phase 1** (TIR enrichment) — immediate code quality improvement, low risk
2. **Phase 2** (RC optimization) — reduces runtime overhead, enables better multi-threading
3. **Phase 4 Step 4.2** (in-memory JIT for REPL) — major UX improvement for interactive use
4. **Phase 3** (LLVM passes) — diminishing returns vs. effort; defer unless benchmarks show need
5. **Phase 5** (PGO) — nice-to-have; defer to post-v1
