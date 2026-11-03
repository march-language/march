# March Implementation Reference

**v1 · 2026-07-06 · compiler-internals index**

---

## What this is

This is the umbrella index over March's **compiler-internals** documentation:
how the compiler and runtime are *built*, as opposed to what the source
language *means*. It is a **sibling** to the language reference
([`specs/lang/index.md`](../lang/index.md)), not part of it: the language
reference describes the surface language, its operational and static semantics,
and its user-facing features; this reference describes value representation,
reference counting, the typed IR, the scheduler, the build cache, and the C
runtime. Language chapters link here where an internal detail is relevant;
internals are never duplicated into the language reference.

> **Note on freshness:** the per-file line-counts and file inventories inside
> the documents below are *indicative, not lint-verified*; they drift as the
> compiler grows. Treat the compiler source (`lib/`, `bin/`, `runtime/`) as
> authoritative; these documents explain the design and point at the source.

---

## Documents

| Document | Topic |
|---|---|
| [`docs/value-representation.md`](../../docs/value-representation.md) | Runtime value representation: tagging, boxing, heap-object layout, the uniform vs. natural repr split. |
| [`specs/perceus-invariants.md`](../perceus-invariants.md) | The Perceus reference-counting + FBIP (functional-but-in-place) invariants the RC-insertion and borrow passes must preserve. |
| [`specs/features/tir-invariants.md`](../features/tir-invariants.md) | Structural invariants of the typed IR (TIR) that hold across lowering, monomorphization, defunctionalization, Perceus, and codegen. |
| [`specs/features/compiler-pipeline.md`](../features/compiler-pipeline.md) | End-to-end pipeline map: lexer → parser → desugar → typecheck → refinement checks → TIR lowering → mono → fusion → defun → Perceus → LLVM emission, with a per-pass file inventory. |
| [`specs/features/scheduler.md`](../features/scheduler.md) | The green-thread actor scheduler (work-stealing `march_proc` model). |
| [`specs/features/runtime.md`](../features/runtime.md) | The C runtime: GC, scheduler, HTTP, TLS, and the builtin surface. |
| [`specs/features/content-addressed-system.md`](../features/content-addressed-system.md) | The content-addressed store (CAS): BLAKE3-hashed definition caching, SCC dependency grouping, cache-hit compilation. Wired into `bin/main.ml`. |
| [`specs/features/http-and-networking.md`](../features/http-and-networking.md) | The HTTP server/client stack and networking runtime. |
| [`specs/features/debugger.md`](../features/debugger.md) | The interpreter time-travel debugger (`dbg()`, the debug REPL, trace capture). |

---

These documents live in place (under `docs/` and `specs/features/`); this index
gathers them into one coherent reference rather than moving them. For the
**source language** (syntax, semantics, typing, and user-facing features), see
the language reference: [`specs/lang/index.md`](../lang/index.md).
