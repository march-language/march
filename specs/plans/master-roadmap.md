# Master Roadmap — March Language Implementation

## Overview

This document sequences the work described in the seven implementation plans into a coherent roadmap. It identifies critical paths, parallelization opportunities, and suggested milestones.

**Total estimated effort across all plans: ~360–370 engineering-days**

### Plan Summary

| Plan | Effort | Critical Dependencies |
|------|--------|-----------------------|
| [Capability Security](capability-security-plan.md) | 17.5–21.5 days | None (Phase 4 needs package manager) |
| [Type System Completion](type-system-completion-plan.md) | 31.5 days | None |
| [Concurrency](concurrency-plan.md) | 52.5–57.5 days | None (Phase 5 needs Phase 4) |
| [CAS Integration](cas-integration-plan.md) | 43.5 days | None |
| [Optimization](optimization-plan.md) | 61–62 days | LLVM bindings for JIT |
| [Stdlib Expansion](stdlib-expansion-plan.md) | 79 days | Type system (interfaces) |
| [Tooling](tooling-plan.md) | 75 days | None |

---

## Critical Path

The longest dependency chain determines the minimum time to "feature complete":

```
Type System Part A (Interface Constraints, 12 days)
    → Stdlib Phase 1 (Standard Interfaces, 8 days)
        → Stdlib Phase 3 (Collections / Map, 18 days)
            → Stdlib Phase 5.1 (JSON, 8 days)
```

This is 46 days on the critical path. However, many plans can run in parallel.

---

## Dependency Graph

```
                    ┌──────────────────────┐
                    │   Type System        │
                    │   Part C: Constructors│
                    │   (6.5 days)         │
                    └──────────────────────┘
                              │ unblocks library development
                              ▼
┌────────────────┐   ┌──────────────────────┐   ┌─────────────────┐
│  Capability    │   │   Type System        │   │  CAS Integration│
│  Phase 1:      │   │   Part A: Interfaces │   │  Phase 1: Wire  │
│  Transitive    │   │   (12 days)          │   │  into pipeline  │
│  (3.5 days)    │   └──────────────────────┘   │  (10 days)      │
└────────────────┘              │                └─────────────────┘
        │                       │                        │
        ▼                       ▼                        ▼
┌────────────────┐   ┌──────────────────────┐   ┌─────────────────┐
│  Capability    │   │  Stdlib Phase 1:     │   │  CAS Phase 2-3: │
│  Phase 2:      │   │  Standard Interfaces │   │  Lockfile, sig/ │
│  Call-graph    │   │  (8 days)            │   │  impl hash      │
│  (6 days)      │   └──────────────────────┘   │  (10.5 days)    │
└────────────────┘        │            │        └─────────────────┘
                          │            │                 │
                          ▼            ▼                 ▼
                   ┌───────────┐ ┌───────────┐   ┌─────────────────┐
                   │ Stdlib    │ │ Stdlib    │   │  CAS Phase 4:   │
                   │ Phase 2:  │ │ Phase 3:  │   │  Package Manager│
                   │ Strings   │ │ Collections│  │  (13 days)      │
                   │ (21 days) │ │ (18 days) │   └─────────────────┘
                   └───────────┘ └───────────┘          │
                                      │                 ▼
                                      ▼          ┌─────────────────┐
                               ┌───────────┐     │  Capability     │
                               │ Stdlib    │     │  Phase 4:       │
                               │ Phase 5:  │     │  Manifest       │
                               │ JSON etc. │     │  (5 days)       │
                               │ (26 days) │     └─────────────────┘
                               └───────────┘

┌───────────────────────────────────────────────────────────────────┐
│                    PARALLEL TRACK: Concurrency                    │
│                                                                   │
│  Phase 1: Mailbox (7d) → Phase 2: Multi-thread (15d)            │
│       │                         │                                │
│       ▼                         ▼                                │
│  Phase 4: Supervision (11d)  Phase 3: Atomic RC (13d)           │
│       │                                                          │
│       ▼                                                          │
│  Phase 5: Epochs (11.5d)                                        │
└───────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────┐
│                    PARALLEL TRACK: Optimization                   │
│                                                                   │
│  Phase 1: TIR enrichment (14d)  →  Phase 2: RC opt (7d)         │
│                                         │                        │
│                                         ▼                        │
│  Phase 4: JIT (26d)              Phase 3: LLVM passes (9d)      │
└───────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────┐
│                    PARALLEL TRACK: Tooling                        │
│                                                                   │
│  Phase 1: LSP (30d)  →  Phase 4: Multi-editor (6d)              │
│  Phase 2: Formatter (12d)                                        │
│  Phase 3: Doc generator (10d)                                    │
│  Phase 6: Linter (6d)                                            │
└───────────────────────────────────────────────────────────────────┘
```

---

## Suggested Milestones

### Milestone 1: "Correct Foundations" (Weeks 1–4) — ✅ SUBSTANTIALLY COMPLETE

Focus: Fix the type system and make existing features correct.

| Work Item | Plan | Effort | Status |
|-----------|------|--------|--------|
| Type-qualified constructors (Part C — codegen) | Type System | 6.5 days | ✅ DONE (Track B, commit 2c710f7) |
| Interface constraint discharge (Part A, Steps 1–3) | Type System | 7 days | ✅ DONE (Track A, commit d8e4566) |
| Linear type fixes (patterns + closures) | Type System | — | ✅ DONE (Track A, commit d8e4566) |
| Wire CAS into default compilation (Phase 1) | CAS | 10 days | ✅ DONE (Track D) |
| Atomic RC in C runtime (Phase 3, Step 3.1) | Concurrency | 1 day | ✅ DONE (Track C) |
| FBIP race fix, scheduler race fix, message RC fix | Concurrency | — | ✅ DONE (Track C) |
| Multi-message scheduling (starvation fix) | Concurrency | — | ✅ DONE (Track C) |
| Transitive capability checking (Phase 1) | Capability | 3.5 days | ❌ Not yet started |

**Delivered**:
- ✅ Constructor name collisions fixed — library development unblocked
- ✅ Interface constraints enforced at call sites
- ✅ Linear types work in patterns and closures (12 new tests)
- ✅ CAS caching working — faster recompilation (all 401+ tests pass)
- ✅ Thread-safe RC operations in the runtime (passed ThreadSanitizer)
- ✅ Actor runtime race conditions fixed (FBIP, scheduler, message send)

### Milestone 2: "Usable Language" (Weeks 5–10)

Focus: Make the language practical for real programs.

| Work Item | Plan | Effort | Parallel? |
|-----------|------|--------|-----------|
| Standard interfaces (Eq, Ord, Show, Hash) | Stdlib | 8 days | Track A |
| String interpolation | Stdlib | 5 days | Track A |
| Short string optimization | Stdlib | 5 days | Track A |
| Persistent Map (HAMT) | Stdlib | 8 days | Track A |
| Mailbox wiring + scheduler integration | Concurrency | 7 days | Track B |
| TIR optimization enrichment | Optimization | 14 days | Track C |
| LSP basics (diagnostics, hover, go-to-def) | Tooling | 14 days | Track D |
| Lockfile support | CAS | 3.5 days | Track C |

**Key deliverables**:
- Programs can use Map, string interpolation, sorted collections
- Actors use proper mailbox-based messaging
- Editor support with error highlighting and hover types
- Measurable compiler optimization improvements

### Milestone 3: "Concurrent & Safe" (Weeks 11–16)

Focus: Multi-threading, supervision, and safety.

| Work Item | Plan | Effort | Parallel? |
|-----------|------|--------|-----------|
| Session type validation (Part B) | Type System | 13 days | Track A |
| Supervision trees | Concurrency | 11 days | Track B |
| Multi-threaded scheduler | Concurrency | 15 days | Track B |
| Capability call-graph inference | Capability | 6 days | Track A |
| Formatter | Tooling | 12 days | Track C |
| File I/O enhancement | Stdlib | 6 days | Track D |
| Persistent Set, Queue | Stdlib | 5 days | Track D |

**Key deliverables**:
- Multi-threaded actor execution with work-stealing
- Supervision trees with restart strategies
- Session type protocols verified at compile time
- Capability flow analysis prevents capability leaks
- Code formatter for consistent style

### Milestone 4: "Production Ready" (Weeks 17–24)

Focus: Polish, ecosystem, and performance.

| Work Item | Plan | Effort | Parallel? |
|-----------|------|--------|-----------|
| Package manager foundation | CAS | 13 days | Track A |
| Epochs and drop handlers | Concurrency | 11.5 days | Track B |
| Biased RC + per-actor arenas | Concurrency | 8 days | Track B |
| JSON module | Stdlib | 8 days | Track C |
| Time, Random, Env, Process modules | Stdlib | 14 days | Track C |
| LSP advanced (references, rename, actions) | Tooling | 17 days | Track D |
| VS Code extension | Tooling | 3 days | Track D |
| Doc generator | Tooling | 10 days | Track D |
| Manifest + capability approval | Capability | 7 days | Track A |

**Key deliverables**:
- Package management with content-addressed dependencies
- Rich stdlib covering common programming tasks
- Full-featured editor experience in VS Code and Zed
- API documentation generation
- Epoch-based fault tolerance for actor systems

### Milestone 5: "Optimized" (Weeks 25–32, partially deferred)

Focus: Performance optimization, advanced features.

| Work Item | Plan | Effort | Parallel? |
|-----------|------|--------|-----------|
| In-memory JIT for REPL | Optimization | 15 days | Track A |
| RC operation optimization | Optimization | 7 days | Track B |
| LLVM pass customization | Optimization | 9 days | Track B |
| Rope string type | Stdlib | 5 days | Track C |
| Mutable Array type | Stdlib | 5 days | Track C |
| Channel module | Stdlib | 4 days | Track C |
| Linter | Tooling | 6 days | Track D |
| LLM integration | Tooling | 11 days | Track D |
| Superclass constraints, associated types | Type System | 6 days | Track A |
| Default method inheritance | Type System | 2 days | Track A |

**Key deliverables**:
- Fast REPL with in-memory compilation
- Optimized RC operations for multi-threaded code
- Complete type system with all interface features
- Comprehensive standard library

---

## Risk Assessment

### High-Risk Items
1. **Multi-threaded scheduler** (Concurrency Phase 2) — Architectural complexity, subtle race conditions
2. **In-memory JIT** (Optimization Phase 4) — LLVM binding challenges, cross-platform issues
3. **Session type validation** (Type System Part B) — Theoretical complexity, protocol recursion

### Medium-Risk Items
4. **Biased RC** (Concurrency Phase 3.2) — Memory ordering subtlety, flushing strategy
5. **HAMT implementation** (Stdlib Phase 3.1) — Algorithm complexity, performance tuning
6. **LSP server** (Tooling Phase 1) — Incremental analysis, performance under load
7. **String interpolation** (Stdlib Phase 2.3) — Lexer state management for nesting
8. **Per-definition CAS caching** (CAS Phase 1.2) — Requires pipeline refactoring

### Low-Risk Items
9. **Atomic RC** (Concurrency Phase 3.1) — Well-understood, one-day change
10. **Lockfile** (CAS Phase 2) — Simple file format
11. **Formatter** (Tooling Phase 2) — Well-known algorithms
12. **Small stdlib modules** (Random, Env, Time) — Straightforward FFI wrappers

---

## Parallelization Strategy

With 2 developers, the optimal pairing per milestone:

**Milestone 1**: Dev A on type system, Dev B on CAS + concurrency
**Milestone 2**: Dev A on stdlib + type system, Dev B on optimization + tooling
**Milestone 3**: Dev A on type system + capability, Dev B on concurrency + tooling
**Milestone 4**: Dev A on CAS + stdlib, Dev B on tooling + concurrency

With a single developer, follow the milestone ordering sequentially, picking the highest-impact items from each milestone first.

---

## What to Skip or Defer

These items provide low value relative to effort and can be safely deferred post-v1:

1. **Remote CAS** (CAS Phase 5) — 10 days, only useful for teams/CI
2. **Profile-guided optimization** (Optimization Phase 5) — 6 days, premature optimization
3. **Multi-party session types** — Explicitly deferred in spec; binary is sufficient for v1
4. **Capability revocation** — Complex runtime implications; static enforcement is sufficient
5. **Rope string type** — Only needed for text editors; basic strings cover 99% of use cases
6. **LLM integration** (Tooling Phase 5) — Innovative but not essential
7. **Tiered JIT compilation** (Optimization Phase 4.4) — 8 days; interpreter + clang JIT is sufficient for v1

---

## Distribution & Installation (Tier 2)

Getting March into users' hands. This is a **Tier 2 priority** — important but comes after the core language features in Tier 1 are solid. A language nobody can install is a language nobody uses, but a language that doesn't work yet isn't worth installing.

### v1 Distribution Target (Items 1–3)

These three items form the minimum viable distribution story. Target completion alongside Milestone 3–4 timeframe.

#### 1. GitHub Releases with Cross-Platform Binaries

- **Effort**: ~3–5 days
- **What**: GitHub Actions CI matrix producing release binaries for:
  - macOS arm64 (Apple Silicon)
  - macOS x86_64 (Intel)
  - Linux x86_64
  - Linux aarch64
- **Approach**: Tag-triggered workflow — push a version tag, CI builds and uploads artifacts to a GitHub Release
- **Dependencies**: Stable enough compiler to ship (Milestone 2+)
- **Why first**: Every other distribution method pulls from releases. This is the foundation.

#### 2. One-Line Install Script (`curl | sh`)

- **Effort**: ~2 days
- **What**: `curl -fsSL https://march-lang.dev/install.sh | sh` that detects OS/arch, downloads the right binary from GitHub Releases, and drops it in `~/.march/bin`
- **Dependencies**: GitHub Releases (item 1)
- **Why**: Lowest friction for new users. Standard for modern language toolchains.

#### 3. Homebrew Formula

- **Effort**: ~1–2 days
- **What**: `brew install march-lang/tap/march` via a custom tap, eventually submit to homebrew-core
- **Dependencies**: GitHub Releases (item 1)
- **Why**: macOS developers expect `brew install`. Tap is day-one; homebrew-core submission comes after the language has traction.

### Post-v1 Distribution (Items 4–6)

#### 4. Nix Flake

- **Effort**: ~2–3 days
- **What**: `nix run github:march-lang/march` or `nix develop` for contributor environments
- **Natural fit**: March's CAS-based build model aligns well with Nix's content-addressed philosophy. The lockfile/hash infrastructure from CAS Phase 2–3 maps almost directly to Nix derivation inputs.
- **Dependencies**: GitHub Releases (item 1); benefits from lockfile support (Tier 1 item 8)

#### 5. Docker Image

- **Effort**: ~1–2 days
- **What**: `docker run ghcr.io/march-lang/march` — minimal image for CI pipelines and containerized builds
- **Dependencies**: GitHub Releases (item 1)

#### 6. Version Manager (`marchup`) — Longer Term

- **Effort**: ~8–12 days
- **What**: Dedicated tool for managing multiple March versions, similar to `rustup`/`ghcup`. Handles toolchain installation, switching between stable/nightly, component management (compiler, LSP, formatter).
- **Dependencies**: Stable release cadence, multiple versions worth managing
- **When**: Post-v1 — only makes sense once there are multiple release channels

### Distribution Effort Summary

| Item | Effort | Target |
|------|--------|--------|
| GitHub Releases + CI | 3–5 days | v1 |
| Install script | 2 days | v1 |
| Homebrew formula | 1–2 days | v1 |
| Nix flake | 2–3 days | Post-v1 |
| Docker image | 1–2 days | Post-v1 |
| Version manager (marchup) | 8–12 days | Post-v1 |
| **Total** | **~17–26 days** | |

---

## Success Criteria

### v0.1 (Milestone 1 complete) — ✅ Substantially achieved
- [x] No constructor name collisions in standard library (Track B, commit 2c710f7)
- [x] Interface constraints checked at call sites (Track A, commit d8e4566)
- [x] CAS caching provides >2x speedup for unchanged code (Track D)
- [x] All 401+ tests passing (confirmed after all four fix tracks)

### v0.5 (Milestone 2 complete)
- [ ] Programs can use `Map`, string interpolation, `Eq`/`Ord`/`Show`
- [ ] Actors use mailbox-based messaging (correct concurrency semantics)
- [ ] LSP provides diagnostics, hover, and go-to-definition
- [ ] Compiler optimizations produce measurable performance improvement

### v0.9 (Milestone 3 complete)
- [ ] Multi-threaded actor execution with supervision trees
- [ ] Session type protocols verified at compile time
- [ ] Capability system prevents unauthorized IO
- [ ] Code formatter enforces consistent style
- [ ] 500+ tests passing

### v1.0 (Milestone 4 complete)
- [ ] Package manager with content-addressed dependencies
- [ ] JSON, Time, Random, File I/O modules in stdlib
- [ ] Full editor experience in VS Code and Zed
- [ ] API documentation generator
- [ ] Epoch-based fault tolerance
- [ ] 700+ tests passing
- [ ] Three non-trivial example applications (HTTP server, actor system, CLI tool)
