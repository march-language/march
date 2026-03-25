# March GC Design

March uses a stratified memory model — no single GC strategy, but layered approaches applied based on what the compiler knows statically. The goal is to eliminate GC overhead entirely for most values, and confine the remaining runtime cost to a small, well-understood subset.

## Design Constraints

The language properties that shape memory management:

- **Linear/affine types** — large fraction of values have statically-known lifetimes
- **Actors with share-nothing message passing** — linear capability send = ownership transfer, so no cross-actor heap pointers ever exist
- **Immutable by default** — no pointer mutations after construction, which eliminates write barriers for the common case
- **Whole-program monomorphization** — all types are concrete at compile time, enabling whole-program escape analysis
- **Defunctionalization** — no heap-allocated closure objects

## Stratified Memory Model

### Layer 1 — Linear/Affine Static Deallocation

Linear and affine values have compiler-inserted `free` at their last use point. This is not GC — it is compile-time resource management with zero runtime overhead.

Covered by this layer:
- Actor capability references (`linear Cap(Actor)`)
- File handles, sockets, foreign pointers entering via FFI
- Any value annotated `linear` or `affine`

The type checker already enforces that linear values are used exactly once and affine values at most once. The backend translates these use-counts directly into `free` insertion. No runtime bookkeeping required.

### Layer 2 — Perceus Reference Counting with FBIP

For unrestricted (non-linear) heap values, March uses **Perceus RC** with the **Functional But In-Place** (FBIP) optimization, as developed for Koka and used in production by Lean 4.

**How Perceus works:**

Standard RC is expensive because every pass of a value increments and then decrements a counter. Perceus performs a static dataflow analysis at compile time to fuse, cancel, and elide RC operations:

- A function that receives a value and immediately returns a transformed version of it can often skip the increment entirely — the caller's reference is transferred
- RC operations that provably cancel (inc followed by dec on the same path) are removed
- The result is that most RC operations disappear statically; only the residual uncertain cases emit runtime instructions

**Functional But In-Place (FBIP):**

When a value's RC hits 0 at the same point a new value of the same shape is being allocated, the runtime reuses the memory in place. From the language's perspective the transformation is pure — the old value is gone, the new value is fresh. From the runtime's perspective it is a mutation. This gives:

- Persistent data structure updates at the cost of a single allocation check
- No allocator round-trip for the common "transform and return" pattern
- Cache locality: the new value occupies the same address as the old one

**Interaction with immutability:**

Immutable-by-default means pointer fields are never written after construction. This eliminates write barriers on the common path. RC adjustments are the only pointer-related runtime cost, and Perceus minimizes those statically.

**Interaction with linear types:**

Linear values have RC = 1 by construction — the type system enforces it. The Perceus analysis can exploit this: no RC increment is ever needed when passing a linear value, because the caller provably loses its reference on transfer. Linear types make Perceus strictly more effective.

### Layer 3 — Per-Actor Arena Heaps

Each actor owns a private bump-pointer arena. Allocation inside an actor is a pointer increment — approximately 2 instructions, no locks, no synchronization.

The critical property: because actor message sending uses linear capabilities (ownership transfer), **no cross-actor pointers exist**. This is not a convention — the type system enforces it. Consequences:

- Each actor's heap is fully self-contained
- Per-actor collection requires no coordination with other actors
- Actor death frees the entire arena in a single `munmap` or equivalent — O(1) regardless of live data
- Per-actor minor collection (if needed) is trivially parallelizable

This validates the BEAM/Erlang model with a stronger static guarantee: where Erlang relies on discipline and convention to avoid shared state, March enforces it via the type system.

### Layer 4 — Escape Analysis and Stack Allocation

With whole-program compilation, the compiler can prove that many values do not escape their allocation scope. Such values are stack-allocated with no heap involvement.

Candidates:
- Temporary values in pure expression evaluation
- Intermediate results in a pipe chain
- Values whose lifetime is bounded by a single function call

Stack allocation is free from the GC's perspective — the stack frame cleanup handles it.

## The Cycle Problem

Perceus RC has the standard cycle limitation. March-specific mitigations make this a non-issue in practice:

1. **Immutable data structures cannot form pointer cycles.** Cycles require a mutable back-pointer — you cannot close a cycle if you cannot write to an already-constructed value. Purely functional values form DAGs.

2. **Linear values cannot participate in cycles.** A cycle requires two or more owners of the same value. Linear types enforce exactly-one-owner. So linear values are structurally excluded from cycles.

3. **Inter-actor references are linear capabilities, not raw pointers.** The only way to reference another actor is through a `Cap`, which is linear. You cannot store a `Cap` in a data structure while simultaneously holding it — that would violate linearity. Inter-actor cycles are structurally impossible.

For any residual case (unrestricted mutable values, if March ever exposes them via uniqueness retyping): a **deferred cycle collector** runs per-actor on idle or when pressure exceeds a threshold. This is the same approach used by CPython and Swift's weak-reference cycle detector. It never touches the fast path and is bounded to the actor's own heap.

## Allocation and Deallocation Fast Paths

| Value kind | Allocation | Deallocation |
|---|---|---|
| Linear/affine | bump pointer in actor arena | compiler-inserted `free` at last use |
| Unrestricted, non-escaping | stack frame | stack unwind |
| Unrestricted, heap | bump pointer in actor arena | Perceus RC (often statically elided) |
| Actor itself | OS-level arena | `arena_free` on actor death |

## Comparison with Alternatives

### Tracing GC (e.g. OCaml's minor/major)
- Requires stop-the-world pauses (or complex concurrent barriers)
- Write barriers on every pointer store — conflicts with immutable-by-default
- Cross-actor roots would require a global root set — incompatible with actor isolation
- Rejected: pauses and write barrier cost are incompatible with March's design goals

### Pure Region Inference (Tofte-Talpin)
- Region inference is undecidable in general and requires constraint solving
- Region annotations leak into the type system and programmer-visible API
- Perceus achieves similar or better results without programmer annotation
- Rejected: implementation complexity without sufficient benefit over Perceus

### Naive Reference Counting
- RC on every inc/dec is high throughput cost
- No reuse optimization — allocation and deallocation are separate operations
- Rejected in favor of Perceus, which subsumes naive RC

### Immix (mark-region tracing)
- Very cache-friendly, low fragmentation, good throughput
- Still requires stop-the-world or concurrent barriers
- Could serve as the cycle collector backend if deferred collection is needed
- Not the primary strategy, but worth evaluating for the deferred cycle pass

## Prior Art

- **Koka** — originates Perceus RC and FBIP; the closest published implementation to this design
- **Lean 4** — production compiler using Perceus RC; demonstrates viability at scale
- **BEAM/Erlang** — per-process heaps with no shared mutable state; validates the actor-isolation model
- **Lobster** — lifetime inference + RC elision via static analysis; demonstrates that static analysis can eliminate the majority of RC overhead
- **MLKit** — region-based memory management for Standard ML; reference point for region inference trade-offs

## Open Questions

1. **Deferred cycle collector algorithm**: trial deletion (Bacon-Rajan) vs. mark-sweep local to the actor heap?
2. **Arena growth policy**: fixed-size slabs vs. doubling arenas vs. per-size-class pools?
3. **Large object handling**: values above a threshold (e.g. 1 MB) may bypass the bump-pointer arena and go directly to the OS. Threshold TBD.
4. **FFI and foreign heaps**: foreign pointers enter as linear values (enforced by the type system), but the foreign allocator's lifecycle may not align with March's. The linear type ensures the pointer is freed exactly once — the question is which `free` function to call.
5. **Profiling hooks**: content-addressed code enables allocation profiling keyed by definition hash — the same function at the same type always produces the same code, so allocation profiles are reproducible across builds.

---

## Phase 5 Implementation Notes (2026-03-25)

Layer 3 (Per-Actor Arena Heaps) has been implemented.  The following notes record how the design was realized and where it diverges from or refines the spec above.

### Arena growth policy (Open Question 2 — resolved)

The implementation uses **doubling arenas** from 64 KiB to 4 MiB (capped):

```
MARCH_HEAP_BLOCK_MIN = 64 KiB   (first block)
MARCH_HEAP_BLOCK_MAX = 4 MiB    (ceiling)
```

Each new block is twice the previous until the cap.  Oversized single allocations (larger than the current cap) get their own dedicated block.  This bounds external fragmentation (wasted space between blocks) to a constant factor while keeping allocation fast.

### Per-allocation metadata

A hidden `march_alloc_meta` (8 bytes) is stored immediately before each user-visible object.  The user pointer (returned by `march_process_alloc`) points to the `march_hdr`, not the meta.  The macro `MARCH_ALLOC_META(p)` recovers the meta from a user pointer.

The meta records:
- `alloc_size` (uint32): total allocation size including the meta prefix and alignment padding
- `n_fields` (uint32): number of 8-byte fields after the 16-byte `march_hdr`

This enables the arena to be walked for GC without any external type table.

### Semi-space GC and Open Question 1

Open Question 1 (deferred cycle collector algorithm) is not yet answered — the Phase 5 GC is not a cycle collector.  It is a compacting semi-space GC that leverages Perceus RC to identify live objects: any object with `rc > 0` is live.  Because March's immutable-by-default design prevents cycles (as analyzed in "The Cycle Problem" above), the semi-space GC is sufficient for most process heaps.

The GC uses the `n_fields` metadata and a forwarding table to update intra-heap pointers during the copy phase.  It never touches other processes' heaps.

### Large object handling (Open Question 3 — deferred)

Large objects currently go through the same arena path as small objects (using an oversized dedicated block).  A bypass to OS-level allocation above a threshold (e.g. 1 MB) is a future optimization.

### Linear message move: zero-copy send

`march_msg_move` implements the zero-copy path for linear messages: it only adjusts `live_bytes` accounting on both heaps and returns the original pointer unchanged.  The linear type system guarantees no aliasing exists, so no data needs to be moved.

The LLVM emitter now chooses between `march_send_linear` (calls `march_msg_move` semantics) and `march_send` (copy semantics) based on the TIR linearity annotation of the message argument.
