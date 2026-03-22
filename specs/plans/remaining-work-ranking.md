# Remaining Work Ranking — March Language Implementation

**Generated**: 2026-03-20
**Basis**: All seven implementation plans + master roadmap completion status
**Scope**: 51 work items, organized by priority into 3 tiers

---

## Summary

Milestone 1 ("Correct Foundations") is substantially complete. The remaining ~310 engineering-days of work span type system completion, concurrency, stdlib, CAS/packaging, optimization, tooling, and capability security. This document ranks every remaining item by a composite score of **Impact** (how much it unblocks or improves the language), **Complexity** (implementation difficulty 1–10), and **Estimated effort** (days).

---

## Tier 1: Do Next (Items 1–10)

These are the highest-leverage items. Completing Tier 1 brings March to "Usable Language" status (Milestone 2) and partially into Milestone 3.

---

### 1. Standard Interfaces (Eq / Ord / Show / Hash)

- **Impact**: 10/10
- **Complexity**: 5/10
- **Estimated effort**: 8 days
- **Plan**: stdlib-expansion-plan.md, Phase 1 (Steps 1.1–1.4)
- **Dependencies**: Interface constraint discharge (✅ done, commit d8e4566)
- **What it blocks**: Persistent Map (needs Hash/Eq), Set, sorted collections, string interpolation (needs Display), JSON module, and essentially every non-trivial user program
- **Parallelizability**: Fully independent of concurrency and tooling tracks. Can start immediately. Steps 1.1–1.2 (define interfaces + primitive impls) are prerequisite for 1.3–1.4 (compound types + Display/Debug).

---

### 2. Mailbox Wiring

- **Impact**: 9/10
- **Complexity**: 6/10
- **Estimated effort**: 7 days
- **Plan**: concurrency-plan.md, Phase 1 (Steps 1.1–1.3)
- **Dependencies**: None — mailbox infrastructure already exists (Michael-Scott queue in `mailbox.ml`)
- **What it blocks**: Supervision trees, multi-threaded scheduler, epochs, correct actor semantics. Currently actors use synchronous send which is semantically wrong.
- **Parallelizability**: Fully independent of type system and stdlib tracks. Step 1.3 (integrate scheduler into eval) is the riskiest sub-step — significant architectural change to the interpreter.

---

### 3. Transitive Capabilities

- **Impact**: 8/10
- **Complexity**: 4/10
- **Estimated effort**: 3.5 days
- **Plan**: capability-security-plan.md, Phase 1 (Steps 1.1–1.3)
- **Dependencies**: None
- **What it blocks**: Call-graph capability inference (Phase 2), manifest system, pure-by-default guarantee. Without this, `needs` declarations are decorative — a module can call IO functions transitively without declaring them.
- **Parallelizability**: Small enough for a single developer in under a week. Independent of all other tracks.

---

### 4. Persistent Map (HAMT)

- **Impact**: 8/10
- **Complexity**: 7/10
- **Estimated effort**: 8 days
- **Plan**: stdlib-expansion-plan.md, Phase 3, Step 3.1
- **Dependencies**: Standard Interfaces (item 1) — Map requires Hash and Eq on keys
- **What it blocks**: Set (trivial wrapper), JSON module (Object needs Map), package manager internals, and any user program needing key-value storage
- **Parallelizability**: Depends on item 1 completing Steps 1.1–1.2 (Hash/Eq for primitives). The HAMT implementation itself is self-contained — mostly runtime C code + March wrapper.

---

### 5. Superclass Constraints

- **Impact**: 7/10
- **Complexity**: 2/10
- **Estimated effort**: 1 day
- **Plan**: type-system-completion-plan.md, Part A, Step A.4
- **Dependencies**: Interface constraint discharge (✅ done)
- **What it blocks**: Correct interface hierarchies (`Ord requires Eq`), stdlib interface design, user-defined interface inheritance
- **Parallelizability**: Tiny change — single function addition in typecheck.ml. Can be done as a quick win alongside any other type system work.

---

### 6. Linear Types in Records

- **Impact**: 7/10
- **Complexity**: 5/10
- **Estimated effort**: 3 days
- **Plan**: type-system-completion-plan.md, Linear + Affine Dual Design section (H6 in correctness audit)
- **Dependencies**: Linear type fixes in patterns/closures (✅ done, Track A)
- **What it blocks**: Safe file handles in records, session channel structs, resource-managing data types, mutable Array type
- **Parallelizability**: Independent of concurrency and stdlib. Touches `typecheck.ml` linearity tracking — orthogonal to interface work.

---

### 7. String Interpolation

- **Impact**: 7/10
- **Complexity**: 6/10
- **Estimated effort**: 5 days
- **Plan**: stdlib-expansion-plan.md, Phase 2, Step 2.3
- **Dependencies**: Display interface (item 1, Step 1.4) for `${expr}` to call `Display.show`
- **What it blocks**: Ergonomic string construction, user-facing output, logging, debugging. Currently all string building requires manual `string_concat` calls.
- **Parallelizability**: Touches lexer/parser/desugar — doesn't conflict with type checker or runtime changes. Can run in parallel with concurrency work.

---

### 8. Lockfile Support

- **Impact**: 6/10
- **Complexity**: 3/10
- **Estimated effort**: 3.5 days
- **Plan**: cas-integration-plan.md, Phase 2 (Steps 2.1–2.4)
- **Dependencies**: CAS wired into pipeline (✅ done, Track D)
- **What it blocks**: Reproducible builds, `--locked` flag, package manager foundation (Phase 4 needs lockfiles)
- **Parallelizability**: Fully independent. Small, self-contained work in `lib/cas/lockfile.ml` + `bin/main.ml`.

---

### 9. TIR Optimization Enrichment

- **Impact**: 6/10
- **Complexity**: 5/10
- **Estimated effort**: 14 days
- **Plan**: optimization-plan.md, Phase 1 (Steps 1.1–1.5)
- **Dependencies**: None — existing TIR optimizer infrastructure is in place
- **What it blocks**: Measurable compiler performance improvements, RC optimization (Phase 2 benefits from better TIR), compiled code quality
- **Parallelizability**: Five independent sub-passes (algebraic simplification, constant propagation, CSE, inlining heuristics, loop optimization). Multiple passes can be developed simultaneously. Entire track is independent of type system and concurrency.

---

### 10. LSP Foundation

- **Impact**: 7/10
- **Complexity**: 6/10
- **Estimated effort**: 14 days (Steps 1.1–1.5 of Phase 1)
- **Plan**: tooling-plan.md, Phase 1
- **Dependencies**: None for basic diagnostics/hover/go-to-def. Hover types benefit from type threading in the type checker.
- **What it blocks**: Editor experience in any IDE, VS Code extension (Phase 4), multi-editor support, developer adoption
- **Parallelizability**: Fully independent track. Steps 1.1–1.2 (project setup + diagnostics) are prerequisites; 1.3–1.5 (go-to-def, hover, completion) can be parallelized after that.

---

## Tier 2: Important Follow-ups (Items 11–31)

These build on Tier 1 and bring the language to "Concurrent & Safe" (Milestone 3) and into "Production Ready" (Milestone 4).

---

### 11. Session Type Validation

- **Impact**: 7/10
- **Complexity**: 8/10
- **Estimated effort**: 13 days
- **Plan**: type-system-completion-plan.md, Part B (Steps B.1–B.5)
- **Dependencies**: Constraint collection (✅ done); mailbox wiring (item 2) for meaningful testing
- **What it blocks**: Compile-time protocol verification, deadlock detection, safe actor communication
- **Parallelizability**: Heavy type-system work — conflicts with other typecheck.ml changes. Best sequenced after items 5–6.

---

### 12. Supervision Trees

- **Impact**: 8/10
- **Complexity**: 6/10
- **Estimated effort**: 11 days
- **Plan**: concurrency-plan.md, Phase 4 (Steps 4.1–4.4)
- **Dependencies**: Mailbox wiring (item 2) — needs mailbox-based actors for monitor/link messages
- **What it blocks**: Fault-tolerant actor systems, epochs, restart strategies — a key language differentiator
- **Parallelizability**: Follows item 2 on the concurrency track. Independent of type system and stdlib.

---

### 13. Persistent Set

- **Impact**: 5/10
- **Complexity**: 2/10
- **Estimated effort**: 2 days
- **Plan**: stdlib-expansion-plan.md, Phase 3, Step 3.2
- **Dependencies**: Map (item 4) — implemented as `Map(a, Unit)` wrapper
- **What it blocks**: Membership queries, deduplication, graph algorithms in user code
- **Parallelizability**: Trivial once Map exists.

---

### 14. Short String Optimization

- **Impact**: 5/10
- **Complexity**: 6/10
- **Estimated effort**: 5 days
- **Plan**: stdlib-expansion-plan.md, Phase 2, Step 2.1
- **Dependencies**: None
- **What it blocks**: String performance for small strings (≤15 bytes inline, no heap allocation)
- **Parallelizability**: Pure C runtime work — independent of everything else.

---

### 15. Call-Graph Capability Inference

- **Impact**: 6/10
- **Complexity**: 7/10
- **Estimated effort**: 6 days
- **Plan**: capability-security-plan.md, Phase 2 (Steps 2.1–2.3)
- **Dependencies**: Transitive capabilities (item 3)
- **What it blocks**: Precise capability error messages, fine-grained `needs` enforcement, pure-by-default guarantee at function level
- **Parallelizability**: Replaces the stub in `lib/effects/effects.ml`. Independent of concurrency and stdlib.

---

### 16. Multi-Threaded Scheduler

- **Impact**: 8/10
- **Complexity**: 9/10
- **Estimated effort**: 15 days
- **Plan**: concurrency-plan.md, Phase 2 (Steps 2.1–2.4)
- **Dependencies**: Mailbox wiring (item 2)
- **What it blocks**: Real parallelism, work-stealing, actor affinity/migration
- **Parallelizability**: High-risk, high-reward. Should be sequenced after mailbox wiring stabilizes. Independent of type system.

---

### 17. Associated Types

- **Impact**: 5/10
- **Complexity**: 6/10
- **Estimated effort**: 3 days
- **Plan**: type-system-completion-plan.md, Part A, Step A.5
- **Dependencies**: Constraint discharge (✅ done)
- **What it blocks**: `Mappable.Element`, `Iterable.Item`, and other advanced interface patterns
- **Parallelizability**: Type system work — schedule with other type checker changes.

---

### 18. Default Method Inheritance

- **Impact**: 4/10
- **Complexity**: 3/10
- **Estimated effort**: 2 days
- **Plan**: type-system-completion-plan.md, Part A, Step A.6
- **Dependencies**: None beyond existing interface infrastructure
- **What it blocks**: Ergonomic interface impls — users must currently implement every method even when defaults would suffice
- **Parallelizability**: Small change in typecheck.ml + desugar.ml. Quick win.

---

### 19. Scoped File I/O

- **Impact**: 5/10
- **Complexity**: 3/10
- **Estimated effort**: 6 days
- **Plan**: stdlib-expansion-plan.md, Phase 4 (Steps 4.1–4.3)
- **Dependencies**: None (linear types in records — item 6 — would enhance but aren't required)
- **What it blocks**: Safe resource cleanup, streaming file operations, FileError ADT
- **Parallelizability**: Independent stdlib work. Touches `file.march` + C runtime only.

---

### 20. Epochs and Drop Handlers

- **Impact**: 6/10
- **Complexity**: 6/10
- **Estimated effort**: 11.5 days
- **Plan**: concurrency-plan.md, Phase 5 (Steps 5.1–5.4)
- **Dependencies**: Supervision trees (item 12)
- **What it blocks**: Epoch-stamped capabilities, resource cleanup on crash, LiveCap pattern
- **Parallelizability**: Follows supervision on the concurrency track.

---

### 21. Formatter

- **Impact**: 5/10
- **Complexity**: 5/10
- **Estimated effort**: 12 days
- **Plan**: tooling-plan.md, Phase 2 (Steps 2.1–2.3)
- **Dependencies**: None
- **What it blocks**: Consistent code style, `march fmt` command, community code consistency
- **Parallelizability**: Independent tooling track. Comment preservation is the hardest sub-problem.

---

### 22. Sig/Impl Hash Separation

- **Impact**: 5/10
- **Complexity**: 6/10
- **Estimated effort**: 7 days
- **Plan**: cas-integration-plan.md, Phase 3 (Steps 3.1–3.3)
- **Dependencies**: CAS wired in (✅ done)
- **What it blocks**: Efficient incremental compilation — implementation-only changes don't force downstream recompilation
- **Parallelizability**: Independent CAS work.

---

### 23. Queue and Deque

- **Impact**: 4/10
- **Complexity**: 3/10
- **Estimated effort**: 3 days
- **Plan**: stdlib-expansion-plan.md, Phase 3, Step 3.3
- **Dependencies**: None
- **What it blocks**: Efficient FIFO/double-ended data structures for user programs
- **Parallelizability**: Independent. Banker's deque is a well-known algorithm.

---

### 24. Zero-Copy Substrings

- **Impact**: 4/10
- **Complexity**: 5/10
- **Estimated effort**: 3 days
- **Plan**: stdlib-expansion-plan.md, Phase 2, Step 2.2
- **Dependencies**: None (benefits from SSO — item 14 — but not required)
- **What it blocks**: Efficient string slicing, parser combinators, text processing
- **Parallelizability**: Pure C runtime work.

---

### 25. IOList Enhancement

- **Impact**: 4/10
- **Complexity**: 3/10
- **Estimated effort**: 3 days
- **Plan**: stdlib-expansion-plan.md, Phase 2, Step 2.4
- **Dependencies**: None
- **What it blocks**: Efficient string building (builder pattern), HTML/template generation
- **Parallelizability**: Independent stdlib/runtime work.

---

### 26. RC Operation Optimization

- **Impact**: 5/10
- **Complexity**: 6/10
- **Estimated effort**: 7 days
- **Plan**: optimization-plan.md, Phase 2 (Steps 2.1–2.3)
- **Dependencies**: Atomic RC (✅ done); benefits from TIR enrichment (item 9)
- **What it blocks**: Multi-threaded RC performance, reduced runtime overhead
- **Parallelizability**: Independent optimization track.

---

### 27. Type-Qualified Constructor Disambiguation

- **Impact**: 4/10
- **Complexity**: 5/10
- **Estimated effort**: 6.5 days
- **Plan**: type-system-completion-plan.md, Part C (Steps C.1–C.4)
- **Dependencies**: Codegen collision fixed (✅ done, Track B)
- **What it blocks**: Clean error messages for ambiguous constructors, `Type.Constructor` syntax in type checker
- **Parallelizability**: Type system work — schedule with other typecheck.ml changes.

---

### 28. VS Code Extension

- **Impact**: 6/10
- **Complexity**: 2/10
- **Estimated effort**: 3 days
- **Plan**: tooling-plan.md, Phase 4, Step 4.1
- **Dependencies**: LSP foundation (item 10) for full functionality; tree-sitter grammar (✅ exists)
- **What it blocks**: Largest editor market share — critical for adoption
- **Parallelizability**: Depends on LSP being functional. Mostly packaging/config work.

---

### 29. Biased Reference Counting

- **Impact**: 5/10
- **Complexity**: 7/10
- **Estimated effort**: 8 days (Steps 3.2–3.3 combined)
- **Plan**: concurrency-plan.md, Phase 3, Steps 3.2–3.3
- **Dependencies**: Multi-threaded scheduler (item 16) for meaningful testing
- **What it blocks**: Fast thread-local RC, per-actor arenas, reduced atomic contention
- **Parallelizability**: Follows multi-threading on the concurrency track.

---

### 30. Package Manager Foundation

- **Impact**: 7/10
- **Complexity**: 7/10
- **Estimated effort**: 13 days
- **Plan**: cas-integration-plan.md, Phase 4 (Steps 4.1–4.4)
- **Dependencies**: Lockfile (item 8), sig/impl hash (item 22)
- **What it blocks**: `march install`, dependency resolution, ecosystem growth, capability manifest
- **Parallelizability**: Depends on CAS track completion. Large enough to warrant dedicated focus.

---

### 31. Distribution & Installation

- **Impact**: 7/10
- **Complexity**: 3/10
- **Estimated effort**: 17–26 days total (6–9 days for v1 target, remainder post-v1)
- **Plan**: master-roadmap.md, Distribution & Installation section
- **Dependencies**: Stable compiler (Milestone 2+); lockfile (item 8) benefits Nix flake
- **What it blocks**: User adoption, contributor onboarding, CI integration, ecosystem growth. A language nobody can install doesn't get used.
- **v1 target**: GitHub Releases with cross-platform binaries (macOS arm64/x86_64, Linux x86_64/aarch64) via GitHub Actions, one-line install script (`curl | sh`), Homebrew formula
- **Post-v1**: Nix flake (natural fit with CAS design), Docker image, version manager (`marchup`)
- **Parallelizability**: Fully independent of all language implementation tracks. Can be done by anyone with CI/packaging experience. GitHub Releases are the foundation — install script and Homebrew both pull from releases.

---

## Tier 3: Polish and Advanced Features (Items 32–51)

These bring the language to "Production Ready" and "Optimized" status (Milestones 4–5). Many can be deferred post-v1.

---

### 32. JSON Module

- **Impact**: 6/10
- **Complexity**: 5/10
- **Estimated effort**: 8 days
- **Plan**: stdlib-expansion-plan.md, Phase 5, Step 5.1
- **Dependencies**: Map (item 4)
- **What it blocks**: API integration, configuration files, data interchange
- **Parallelizability**: Independent once Map exists.

---

### 33. Doc Generator

- **Impact**: 5/10
- **Complexity**: 4/10
- **Estimated effort**: 10 days
- **Plan**: tooling-plan.md, Phase 3 (Steps 3.1–3.4)
- **Dependencies**: None
- **What it blocks**: API documentation, library ecosystem documentation
- **Parallelizability**: Independent tooling work.

---

### 34. Random Module

- **Impact**: 4/10
- **Complexity**: 2/10
- **Estimated effort**: 3 days
- **Plan**: stdlib-expansion-plan.md, Phase 5, Step 5.2
- **Dependencies**: Capability system for `Cap(Random)` gating (item 3 minimal)
- **What it blocks**: Games, simulations, testing, sampling
- **Parallelizability**: Small, independent FFI wrapper.

---

### 35. Time Module

- **Impact**: 4/10
- **Complexity**: 3/10
- **Estimated effort**: 4 days
- **Plan**: stdlib-expansion-plan.md, Phase 5, Step 5.3
- **Dependencies**: Capability system for `Cap(IO.Clock)` gating
- **What it blocks**: Timestamps, benchmarking, scheduling, timeouts
- **Parallelizability**: Independent FFI wrapper.

---

### 36. Environment Module

- **Impact**: 4/10
- **Complexity**: 2/10
- **Estimated effort**: 2 days
- **Plan**: stdlib-expansion-plan.md, Phase 5, Step 5.4
- **Dependencies**: Capability system for `Cap(IO.Process)` gating
- **What it blocks**: CLI tools, configuration, deployment
- **Parallelizability**: Tiny, independent.

---

### 37. Process Module

- **Impact**: 4/10
- **Complexity**: 4/10
- **Estimated effort**: 5 days
- **Plan**: stdlib-expansion-plan.md, Phase 5, Step 5.5
- **Dependencies**: Capability system for `Cap(IO.Process)` gating
- **What it blocks**: Subprocess management, build tools, scripting
- **Parallelizability**: Independent FFI wrapper.

---

### 38. Advanced LSP (References, Rename, Code Actions)

- **Impact**: 5/10
- **Complexity**: 6/10
- **Estimated effort**: 12 days (Steps 1.6–1.8)
- **Plan**: tooling-plan.md, Phase 1, Steps 1.6–1.8
- **Dependencies**: LSP foundation (item 10)
- **What it blocks**: Professional-grade editor experience, refactoring support
- **Parallelizability**: Follows LSP foundation. Steps 1.6–1.8 have some internal dependencies (rename needs find-references).

---

### 39. Capability Attenuation

- **Impact**: 4/10
- **Complexity**: 4/10
- **Estimated effort**: 2 days (implicit approach)
- **Plan**: capability-security-plan.md, Phase 3 (Steps 3.1–3.2)
- **Dependencies**: Transitive capabilities (item 3)
- **What it blocks**: Fine-grained capability narrowing (`Cap.narrow`), security-conscious library design
- **Parallelizability**: Small, independent.

---

### 40. Manifest + Capability Approval

- **Impact**: 5/10
- **Complexity**: 4/10
- **Estimated effort**: 5 days
- **Plan**: capability-security-plan.md, Phase 4 (Steps 4.1–4.3)
- **Dependencies**: Package manager (item 30), transitive capabilities (item 3)
- **What it blocks**: Secure package installation, capability grant UI, `march.toml` manifest
- **Parallelizability**: Depends on package manager.

---

### 41. Channel Module

- **Impact**: 4/10
- **Complexity**: 5/10
- **Estimated effort**: 4 days
- **Plan**: stdlib-expansion-plan.md, Phase 5, Step 5.6
- **Dependencies**: Mailbox wiring (item 2)
- **What it blocks**: Synchronous task-to-task communication, Go-style channel patterns
- **Parallelizability**: Follows concurrency Phase 1.

---

### 42. In-Memory JIT for REPL

- **Impact**: 5/10
- **Complexity**: 8/10
- **Estimated effort**: 15 days (Steps 4.1–4.3)
- **Plan**: optimization-plan.md, Phase 4
- **Dependencies**: LLVM bindings/ORC JIT availability
- **What it blocks**: Fast REPL (<10ms vs ~100ms), cross-fragment calls, interactive development
- **Parallelizability**: Independent track, but high-risk.

---

### 43. LLVM Pass Customization

- **Impact**: 4/10
- **Complexity**: 7/10
- **Estimated effort**: 9 days
- **Plan**: optimization-plan.md, Phase 3 (Steps 3.1–3.3)
- **Dependencies**: TIR enrichment (item 9) for metadata
- **What it blocks**: March-specific LLVM optimizations (RC coalescing at IR level, vectorization hints)
- **Parallelizability**: Independent optimization track.

---

### 44. Neovim/Helix Integration

- **Impact**: 3/10
- **Complexity**: 1/10
- **Estimated effort**: 3 days
- **Plan**: tooling-plan.md, Phase 4, Steps 4.2–4.3
- **Dependencies**: LSP foundation (item 10), tree-sitter grammar (✅ exists)
- **What it blocks**: Editor choice for power users
- **Parallelizability**: Trivial config/docs work once LSP exists.

---

### 45. Mutable Array Type

- **Impact**: 4/10
- **Complexity**: 6/10
- **Estimated effort**: 5 days
- **Plan**: stdlib-expansion-plan.md, Phase 3, Step 3.4
- **Dependencies**: Linear types in records (item 6) for safe mutation
- **What it blocks**: O(1) indexed access, numeric computing, FFI interop
- **Parallelizability**: Depends on linearity story. Runtime + stdlib work.

---

### 46. Rope String Type

- **Impact**: 3/10
- **Complexity**: 6/10
- **Estimated effort**: 5 days
- **Plan**: stdlib-expansion-plan.md, Phase 2, Step 2.5
- **Dependencies**: None
- **What it blocks**: Text editors, large document manipulation
- **Parallelizability**: Independent. Deferrable — only needed for specialized use cases.

---

### 47. Linter

- **Impact**: 3/10
- **Complexity**: 3/10
- **Estimated effort**: 6 days
- **Plan**: tooling-plan.md, Phase 6 (Steps 6.1–6.2)
- **Dependencies**: None
- **What it blocks**: `march lint`, style enforcement, code quality automation
- **Parallelizability**: Independent tooling work.

---

### 48. LLM Integration

- **Impact**: 4/10
- **Complexity**: 5/10
- **Estimated effort**: 11 days
- **Plan**: tooling-plan.md, Phase 5 (Steps 5.1–5.3)
- **Dependencies**: LSP error infrastructure (item 10)
- **What it blocks**: `march assist`, type-aware code generation, structured error context for AI repair
- **Parallelizability**: Independent but experimental.

---

### 49. Actor Spawn Capability Gating

- **Impact**: 3/10
- **Complexity**: 2/10
- **Estimated effort**: 1 day
- **Plan**: capability-security-plan.md, Phase 5
- **Dependencies**: Transitive capabilities (item 3)
- **What it blocks**: Enforcing that spawners have required caps — security correctness
- **Parallelizability**: Tiny, schedule alongside other capability work.

---

### 50. Tiered JIT Compilation

- **Impact**: 3/10
- **Complexity**: 7/10
- **Estimated effort**: 8 days
- **Plan**: optimization-plan.md, Phase 4, Step 4.4
- **Dependencies**: In-memory JIT (item 41)
- **What it blocks**: Adaptive optimization (interpret → quick compile → optimized compile)
- **Parallelizability**: Follows JIT foundation. Deferrable post-v1.

---

### 51. Profile-Guided Optimization

- **Impact**: 2/10
- **Complexity**: 3/10
- **Estimated effort**: 6 days
- **Plan**: optimization-plan.md, Phase 5 (Steps 5.1–5.3)
- **Dependencies**: TIR enrichment (item 9), JIT infrastructure (item 41)
- **What it blocks**: Data-driven optimization decisions, production performance tuning
- **Parallelizability**: Independent but low priority. Deferred post-v1.

---

## Parallel Execution Plan — Two Developers, Tier 1 in 6–8 Weeks

### Strategy

Two developers can complete Tier 1 in approximately 6–8 weeks by working across 5 independent tracks. The tracks are designed so that dependencies flow forward in time and cross-track synchronization points are minimized.

### Track Layout

```
Week  Dev A (Type System + Stdlib)           Dev B (Concurrency + Infrastructure)
─────┬────────────────────────────────────────┬──────────────────────────────────────
 1   │ #1 Standard Interfaces (Steps 1.1-1.2) │ #2 Mailbox Wiring (Steps 1.1-1.2)
     │ #5 Superclass Constraints              │
─────┼────────────────────────────────────────┼──────────────────────────────────────
 2   │ #1 Standard Interfaces (Steps 1.3-1.4) │ #2 Mailbox Wiring (Step 1.3)
     │                                        │ #3 Transitive Capabilities
─────┼────────────────────────────────────────┼──────────────────────────────────────
 3   │ #6 Linear Types in Records             │ #8 Lockfile Support
     │ #7 String Interpolation (start)        │ #9 TIR Optimization (Steps 1.1-1.2)
─────┼────────────────────────────────────────┼──────────────────────────────────────
 4   │ #7 String Interpolation (finish)       │ #9 TIR Optimization (Steps 1.3-1.4)
     │ #4 Persistent Map (start)              │
─────┼────────────────────────────────────────┼──────────────────────────────────────
 5   │ #4 Persistent Map (continue)           │ #9 TIR Optimization (Step 1.5)
     │                                        │ #10 LSP Foundation (Steps 1.1-1.2)
─────┼────────────────────────────────────────┼──────────────────────────────────────
 6   │ #4 Persistent Map (finish)             │ #10 LSP Foundation (Steps 1.3-1.5)
─────┼────────────────────────────────────────┼──────────────────────────────────────
 7-8 │ Buffer / start Tier 2 items            │ #10 LSP Foundation (finish)
─────┴────────────────────────────────────────┴──────────────────────────────────────
```

### Five Independent Tracks

**Track 1: Type System** (Dev A primary)
`Interfaces (#1) → Superclass (#5) → Linear Records (#6) → Session Types (#11)`

Rationale: Each item enriches the type checker, and later items build on earlier ones. Superclass constraints are a quick 1-day win wedged into Week 1. Session types (Tier 2) follow naturally once the interface and linearity stories are complete.

**Track 2: Concurrency** (Dev B primary)
`Mailbox (#2) → Supervision (#12) → Epochs (#20) → Multi-Threaded Scheduler (#16)`

Rationale: Mailbox wiring is the prerequisite for all concurrency work. Supervision and epochs refine the actor model. The multi-threaded scheduler is highest-risk and should come after the single-threaded actor model is correct.

**Track 3: Stdlib / CAS** (Dev A primary)
`Map (#4) → String Interpolation (#7) → Lockfile (#8) → Package CLI (#30)`

Rationale: Map is the most-blocked-on data structure. String interpolation is the most user-visible ergonomic improvement. Lockfile and package manager build on the CAS foundation already in place.

**Track 4: Tooling** (Dev B primary)
`LSP Foundation (#10) → VS Code Extension (#28) → Tree-Sitter updates → LLM Integration (#47)`

Rationale: LSP provides the highest-impact developer experience improvement. VS Code extension is mostly packaging once LSP works. LLM integration is experimental but builds on LSP infrastructure.

**Track 5: Optimization** (Dev B primary)
`TIR Passes (#9) → RC Optimization (#26) → LLVM Tuning (#42) → JIT (#41)`

Rationale: TIR enrichment is low-risk, high-reward. Each subsequent item requires more LLVM expertise and carries higher risk. JIT should come last as it's the highest-risk item.

### Synchronization Points

1. **End of Week 2**: Interfaces available → Map work can begin (Week 3–4 for Dev A)
2. **End of Week 2**: Mailbox complete → Supervision can begin in Tier 2
3. **End of Week 4**: Display interface available → String interpolation can use it
4. **End of Week 6**: LSP diagnostics working → VS Code extension packaging can begin

### Risk Mitigation

- **Mailbox wiring (Step 1.3)** is the riskiest single item — significant interpreter architecture change. Allow 1 extra day buffer in Week 2.
- **HAMT implementation** is algorithmically complex. Fallback: use a simpler balanced BST (red-black tree) with O(log n) instead of O(~1) — still vastly better than List-based lookup.
- **LSP hover types** depend on type information threading. If the type checker doesn't expose span→type maps easily, start with diagnostics-only and add hover later.

---

## Effort Summary

| Tier | Items | Total Effort | Cumulative |
|------|-------|-------------|------------|
| Tier 1 | 1–10 | ~67 days | 67 days |
| Tier 2 | 11–31 | ~145–154 days | 212–221 days |
| Tier 3 | 32–51 | ~115 days | 327–336 days |

With 2 developers working in parallel, Tier 1 is achievable in **6–8 weeks**. Tiers 1+2 together take roughly **18–22 weeks**. The full 51-item backlog represents approximately **9–11 months** of work for a two-person team.
