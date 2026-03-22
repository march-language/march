# Atomic Reference Counting for March

**Date:** 2026-03-21
**Status:** Draft
**Depends on:** Perceus RC (implemented), per-actor arenas (designed), LLVM codegen (implemented), HTTP server (implemented with manual borrow workaround)

## Problem

March's RC operations are currently unconditionally atomic in the C runtime (`march_incrc`/`march_decrc` use `atomic_fetch_add`/`atomic_fetch_sub`), even though the vast majority of RC traffic is actor-local and will never be touched by more than one thread. This is a blunt instrument: atomic instructions on ARM64 cost 5–15× more than a plain `add`/`sub` to L1-hot memory, and the `acq_rel` fences on `march_decrc` add pipeline stalls that propagate across the memory hierarchy. Perceus eliminates most RC ops statically, but the residual ones still pay the atomic tax unconditionally.

The one place where atomics are genuinely needed is the HTTP server's thread-per-connection model, where a shared pipeline closure is invoked concurrently from multiple OS threads. Today this is handled by a manual borrow workaround in `march_http.c` (lines 668–688) that walks the closure's capture tree and calls `march_incrc` on every reachable node before each call. This is fragile, runtime-specific, and invisible to the compiler.

This spec designs a system where the compiler distinguishes actor-local RC (non-atomic, fast) from cross-thread RC (atomic, correct), integrating with Perceus analysis, escape analysis, per-actor arenas, and LLVM codegen.

## Design Constraints

Properties of March that shape the solution:

1. **Share-nothing actors** — the type system enforces that no cross-actor heap pointers exist. Actor message passing transfers ownership via linear capabilities. This means all values reachable from an actor's heap are private to that actor.

2. **Per-actor arena heaps** — each actor's allocations live in a private bump-pointer arena. No other actor or thread touches these allocations. Arena-local values need no atomic RC.

3. **Immutable by default** — no pointer mutations after construction. No write barriers needed. The only pointer-related runtime cost is RC adjustment.

4. **Perceus eliminates most RC ops** — the static analysis already removes the majority of increments and decrements. Only the residual uncertain cases emit runtime operations.

5. **Thread-per-connection HTTP server** — the main case requiring cross-thread RC. A pipeline closure (and its transitive capture set) is shared across N connection threads that execute concurrently. Each thread invokes the closure, and Perceus-inserted `dec_rc` in the callee must not free the closure while other threads still hold references.

6. **Defunctionalization** — closures are heap-allocated structs (`$Clo_...`) with a function pointer and captured variables. After defun, these are regular `TCon` values with `Unr` linearity and standard RC semantics.

## Analysis: Where Are Atomics Actually Needed?

### Case 1: Actor-Local Values (No Atomics Needed)

The vast majority of heap values in a March program are allocated within an actor's arena and never escape the actor. The type system guarantees this: `Cap` is the only way to reference another actor, `Cap` is non-linear but does not create cross-actor heap pointers, and message sending transfers ownership.

Within a single actor, the runtime guarantees single-threaded execution — the scheduler processes one actor turn at a time, and even with the M3 worker pool, each actor is processed by exactly one thread at any moment (the `scheduled` CAS ensures this). Therefore:

**All values allocated within an actor's heap need only non-atomic RC operations.**

This covers: data structures (lists, trees, records), intermediate computation results, actor state, and local closures that don't escape to the HTTP layer.

### Case 2: HTTP Pipeline Closures (Atomics Needed)

The HTTP server accept loop (`march_http_server_listen`) receives a `pipeline` closure and shares it across all connection threads. Each connection thread:

1. Calls `march_incrc(pipeline)` (manual borrow)
2. Manually walks and inc_rc's the closure's captured variables
3. Invokes the closure: `fn(pipeline, conn)`
4. Perceus-inserted `dec_rc` in the callee decrements the closure's RC

The pipeline closure and its entire transitive capture set are accessed concurrently from multiple OS threads. These values require atomic RC.

### Case 3: Future Shared Immutable Data

Even without the HTTP server, future features may introduce shared immutable values:

- **Global constants** (string literals, static configuration) — currently allocated per-use, but a future optimization could share them. These would need atomic RC or static/immortal RC.
- **Cross-actor shared read-only data** — if March ever relaxes the share-nothing constraint for deeply-immutable values (a common optimization in Erlang/BEAM via persistent_term), those values would need atomic RC.

### Case 4: Actor Scheduler Infrastructure

The actor scheduler itself (`march_actor_meta`, message nodes, run queue) already uses atomics correctly at the C level. These are runtime-internal structures, not user-visible values, and are unaffected by this design.

## Strategy: Compiler-Directed RC Mode Selection

The core idea: **the Perceus pass annotates each RC operation with a mode (atomic or non-atomic), and the LLVM codegen emits different instructions accordingly.** The mode is determined by escape analysis — specifically, whether a value can be proven to never escape to a cross-thread context.

### New TIR Nodes

Extend the TIR expression type with an RC mode annotation:

```ocaml
type rc_mode = RcLocal | RcAtomic

type expr =
  | ...
  | EIncRC   of atom * rc_mode    (* was: EIncRC of atom *)
  | EDecRC   of atom * rc_mode    (* was: EDecRC of atom *)
  | EReuse   of atom * ty * atom list * rc_mode
  | ...
```

`RcLocal` emits a plain (non-atomic) load-add-store or load-sub-store sequence. `RcAtomic` emits the current `atomic_fetch_add`/`atomic_fetch_sub` calls. The default for all RC ops is `RcLocal`; only values that escape to a cross-thread context are promoted to `RcAtomic`.

### Escape Classification

A value is **thread-confined** (eligible for `RcLocal`) if all of the following hold:

1. It is allocated within an actor body (not in a top-level `main` function that feeds into `http_server_listen`).
2. It is not passed as an argument to a function known to share its argument across threads (currently only `march_http_server_listen`).
3. It is not reachable from a value that fails conditions (1) or (2).

A value is **thread-shared** (requires `RcAtomic`) if:

1. It is passed (directly or transitively) to `march_http_server_listen` as the pipeline argument.
2. It is captured by a closure that is thread-shared.
3. It is a field of a data structure that is thread-shared.

### Integration Point: Between Perceus and LLVM Emit

The RC mode assignment runs as a lightweight pass after Perceus RC insertion and before LLVM emission. It walks each `fn_def`, identifies values that reach a thread-sharing boundary, and marks their RC ops as `RcAtomic`. Everything else stays `RcLocal`.

```
Lower → Mono → Defun → Perceus RC → RC Mode Assignment → Escape → LLVM emit
```

The RC mode assignment is conservative: if the analysis cannot prove thread-confinement, it falls back to `RcAtomic`. This is safe because atomic operations are correct in the non-contended (single-thread) case — they are just slower.

## Detailed Design

### Phase 1: Annotation Infrastructure

**TIR changes (`lib/tir/tir.ml`):**

```ocaml
type rc_mode = RcLocal | RcAtomic

(* Update existing constructors *)
type expr =
  | ...
  | EIncRC   of atom * rc_mode
  | EDecRC   of atom * rc_mode
  | EReuse   of atom * ty * atom list * rc_mode
  | ...
```

All existing code that constructs `EIncRC`/`EDecRC`/`EReuse` (in `perceus.ml`) defaults to `RcLocal`. The mode assignment pass may upgrade some to `RcAtomic`.

**Backward compatibility:** The Perceus pass itself is unchanged except for adding the `RcLocal` default to its constructors. No algorithmic changes to liveness analysis, RC insertion, elision, or FBIP detection.

### Phase 2: Thread-Sharing Analysis (`lib/tir/rc_mode.ml`)

A new pass that identifies thread-shared values and upgrades their RC ops.

**Algorithm:**

1. **Identify sharing roots.** Scan each `fn_def` for calls to known thread-sharing functions. In v1, the only such function is `march_http_server_listen` (exposed as a builtin). The pipeline argument (argument index 3, the closure) is a sharing root.

2. **Compute the shared set.** Starting from each sharing root, compute the transitive closure of values reachable through:
   - The root variable itself
   - All captured variables of the root (if it's a closure, walk the `$Clo_...` struct fields)
   - All fields of data structures reachable from the root (e.g., the `List(Plug)` stored as a captured var)

   This is a standard reachability analysis over the TIR's type structure. Post-monomorphization, all types are concrete, so the analysis is precise.

3. **Mark RC ops.** Walk each `fn_def` body. For every `EIncRC(v, _)`, `EDecRC(v, _)`, or `EReuse(v, _, _, _)` where `v` is in the shared set, replace the mode with `RcAtomic`.

4. **Propagate through calls.** If a function `f` receives a parameter that is in the shared set at some call site, all RC ops on that parameter within `f` must be `RcAtomic`. This requires a lightweight interprocedural annotation: mark function parameters as potentially-shared, then propagate within the function body.

**Precision notes:**

- In the common case (no HTTP server, pure actor program), the shared set is empty and every RC op stays `RcLocal`. Zero overhead.
- For an HTTP server program, only the pipeline closure and its captures are in the shared set. All actor-internal values remain `RcLocal`.
- The analysis is whole-program (post-monomorphization), which March already requires.

### Phase 3: LLVM Codegen Changes (`lib/tir/llvm_emit.ml`)

**New runtime functions declared in the preamble:**

```llvm
declare void @march_incrc(ptr %p)          ; atomic (existing)
declare void @march_decrc(ptr %p)          ; atomic (existing)
declare i64  @march_decrc_freed(ptr %p)    ; atomic (existing)
declare void @march_incrc_local(ptr %p)    ; non-atomic (new)
declare void @march_decrc_local(ptr %p)    ; non-atomic (new)
declare i64  @march_decrc_freed_local(ptr %p) ; non-atomic (new)
```

**Emission logic:**

```ocaml
| Tir.EIncRC (atom, Tir.RcAtomic) ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_incrc(ptr %s)" v);
    ("i64", "0")

| Tir.EIncRC (atom, Tir.RcLocal) ->
    let (ty, v) = emit_atom ctx atom in
    if ty = "ptr" then
      emit ctx (Printf.sprintf "call void @march_incrc_local(ptr %s)" v);
    ("i64", "0")

(* Same pattern for EDecRC and EReuse *)
```

**FBIP/EReuse:** The conditional reuse check (`march_decrc_freed` → branch) must use the matching atomic/non-atomic variant. The existing codegen for `EReuse` (lines 1021–1075 of `llvm_emit.ml`) calls `march_decrc_freed`; this becomes `march_decrc_freed_local` or `march_decrc_freed` depending on the mode.

### Phase 4: Runtime Changes (`runtime/march_runtime.c`)

**New non-atomic RC functions:**

```c
void march_incrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    ((march_hdr *)p)->rc += 1;
}

void march_decrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    int64_t rc = --((march_hdr *)p)->rc;
    if (rc == 0) {
        free(p);
    } else if (rc < 0) {
        fprintf(stderr, "march: RC underflow (rc=%lld) at %p — aborting\n",
                (long long)rc, p);
        abort();
    }
}

int64_t march_decrc_freed_local(void *p) {
    if (!IS_HEAP_PTR(p)) return 1;
    int64_t rc = --((march_hdr *)p)->rc;
    if (rc <= 0) { free(p); return 1; }
    return 0;
}
```

These are simple load-modify-store sequences with no fences. On ARM64, this compiles to `ldr` + `add`/`sub` + `str` — roughly 3 cycles total vs. 15+ cycles for `ldxr`/`stxr` loop + `dmb` barriers.

**Existing atomic functions remain unchanged.** The `march_incrc`/`march_decrc` functions keep their current `atomic_fetch_add`/`atomic_fetch_sub` implementations. They become the "slow path" used only for thread-shared values.

### Phase 5: Eliminating the HTTP Borrow Workaround

With compiler-directed atomic RC, the manual borrow workaround in `march_http.c` (lines 668–688) can be replaced:

**Before (current):**
```c
/* Manual: walk closure tree, inc_rc everything */
march_incrc(pipeline);
{
    void *p = *(void **)(clo + 24);
    while (p) {
        march_incrc(p);
        /* ... walk Cons spine ... */
    }
}
void *result_conn = fn(pipeline, conn);
```

**After (with atomic RC):**
```c
/* Perceus already inserted the correct inc_rc/dec_rc for the call.
   The pipeline and its captures have RcAtomic mode, so the compiler-emitted
   march_incrc calls are atomic. No manual intervention needed. */
void *result_conn = fn(pipeline, conn);
```

The key insight: the reason the manual workaround exists is that Perceus inserts `dec_rc` in the callee (the pipeline function), which decrements the pipeline's RC. If the pipeline's RC operations are atomic, the decrement is safe — the last thread to decrement to zero frees the pipeline, and all other threads have already finished with it.

However, there is a subtlety: the accept loop holds a reference to `pipeline` indefinitely (it's a parameter to `march_http_server_listen`). The pipeline's RC never reaches zero during the server's lifetime because the accept loop's reference is never released. Perceus knows this — the pipeline parameter is live throughout the accept loop's body, so no `dec_rc` is inserted for the accept loop's reference. The only `dec_rc` calls are in the callee (the pipeline function itself), which decrements the reference passed to it. With atomic RC, these decrements correctly interleave across threads.

The manual borrow workaround for captured variables (walking the Cons spine) is also eliminated because the RC mode assignment propagates `RcAtomic` transitively to all values reachable from the pipeline closure. When Perceus inserts `inc_rc` for a non-last use of a captured variable inside the pipeline function, that `inc_rc` is emitted as `march_incrc` (atomic), and the corresponding `dec_rc` is also atomic.

**One remaining requirement:** the `connection_thread` function must still increment the pipeline's RC before calling it, because each connection thread receives the pipeline via a raw `void *` in the `conn_thread_arg_t`, bypassing Perceus. This single `march_incrc(pipeline)` call at the top of `connection_thread` replaces the entire tree-walking workaround. The decrement is handled by Perceus-inserted code inside the pipeline function.

Actually, a cleaner solution: change `connection_thread` to be a March function (compiled through the normal pipeline) rather than a hand-written C function. Then Perceus handles the RC correctly, and the RC mode assignment marks the pipeline parameter as `RcAtomic`. This is the ideal end state but can be deferred.

## Integration with Per-Actor Arenas

When per-actor arena heaps are fully implemented, the interaction with RC modes is straightforward:

1. **Arena-allocated values** (allocated via `actor_arena_alloc`) are always actor-local. Their RC ops are always `RcLocal`. When the actor dies, the entire arena is freed in O(1) — individual RC decrements are unnecessary.

2. **Non-arena values** (large objects that bypass the arena, or values allocated outside an actor context like the HTTP pipeline) use `march_alloc` (which is `calloc`-based) and follow the normal RC mode selection.

3. **Arena death optimization:** When an actor dies, instead of decrementing RC on every live value, the runtime can simply `munmap` the arena. This is safe because no cross-actor pointers exist (type system guarantee). Values with `RcAtomic` mode are by definition not in any actor's arena (they're in the global heap), so they are unaffected by arena death.

The RC mode assignment pass can use the following heuristic: if a value is allocated within an actor body (detected by the enclosing function being an actor message handler), it is actor-local and gets `RcLocal`. This is a conservative approximation that works for v1.

## Integration with Epochs

Epochs track actor generations for capability staleness. The atomic RC system is orthogonal to epochs:

- Epoch checks happen at `send`/`receive_session` sites, not at RC adjustment sites.
- A stale capability causes a `DeadActor`/`Dead` result, not an RC error.
- The `LiveCap` type is a runtime-internal type managed by the supervisor; it has no heap representation that participates in RC.

No changes to the epoch system are needed.

## Performance Analysis

### Expected Overhead Reduction

**Current state:** All RC ops are atomic. On ARM64 (Apple M-series):
- `atomic_fetch_add` (relaxed): ~5 cycles (uncontended)
- `atomic_fetch_sub` (acq_rel): ~15 cycles (fence cost)
- Total per inc+dec pair: ~20 cycles

**After this change:** Actor-local RC ops are non-atomic:
- Plain `ldr` + `add` + `str`: ~3 cycles
- Total per inc+dec pair: ~6 cycles
- **~3.3× speedup on residual RC operations**

**Qualification:** Perceus already eliminates the majority of RC ops. If Perceus reduces RC traffic by 80%, the remaining 20% see a 3.3× speedup, for an overall ~2.7× speedup on RC-related overhead. Since RC is itself a small fraction of total execution time for most programs (allocation, function calls, and I/O dominate), the end-to-end improvement is likely 2–5% for compute-bound actor programs and negligible for I/O-bound programs.

**The real win** is correctness and maintainability: eliminating the manual borrow workaround in `march_http.c` removes a class of bugs (missed inc_rc on newly captured variables, incorrect tree walking for changed data structure shapes) and makes the HTTP server work automatically with any pipeline structure.

### Benchmark Plan

1. **Micro-benchmark: RC throughput.** Allocate and free N values in a tight loop, measuring cycles per inc/dec pair for atomic vs. non-atomic variants. Target: confirm the 3× difference.

2. **Macro-benchmark: tree traversal.** Build a large balanced tree (1M nodes), then map a function over it. This exercises Perceus's residual RC ops (the non-last-use increments for shared subtrees). Compare atomic-only vs. mixed-mode.

3. **HTTP benchmark: requests/second.** Run the HTTP hello-world server under `wrk` with various concurrency levels. Compare current (atomic + manual borrow) vs. new (mixed-mode, no manual borrow). The HTTP pipeline path should show no regression since it still uses atomic RC.

4. **Actor benchmark: message throughput.** Ring benchmark with N actors passing messages. This exercises actor-local RC (message construction and pattern matching). Expect improvement from non-atomic RC on message values.

## Implementation Phases

### Phase 1: Runtime Functions (1 day)

Add `march_incrc_local`, `march_decrc_local`, `march_decrc_freed_local` to `march_runtime.c`. Add declarations to `march_runtime.h`. All existing callers continue using the atomic variants — no behavior change.

**Deliverable:** Runtime compiles and passes all existing tests.

### Phase 2: TIR Annotation (1 day)

Add `rc_mode` type to `tir.ml`. Update `EIncRC`, `EDecRC`, `EReuse` constructors to carry `rc_mode`. Update all construction sites in `perceus.ml` to default to `RcLocal`. Update all pattern match sites in `llvm_emit.ml`, `perceus.ml` (elision, FBIP), and `pp.ml` (pretty printer) to handle the new field.

**Deliverable:** Compiler builds. All RC ops default to `RcLocal`. LLVM emit calls `march_incrc_local`/`march_decrc_local` for everything. Existing tests pass (non-atomic is correct for single-threaded tests). HTTP server tests may break (expected — addressed in Phase 4).

### Phase 3: LLVM Codegen Dispatch (0.5 day)

Update `llvm_emit.ml` to emit `march_incrc` vs. `march_incrc_local` (and corresponding `decrc`/`decrc_freed` variants) based on the `rc_mode` annotation on each TIR node.

**Deliverable:** Codegen correctly dispatches between atomic and non-atomic variants.

### Phase 4: RC Mode Assignment Pass (2–3 days)

Implement `lib/tir/rc_mode.ml`:

1. Identify thread-sharing builtins (hardcoded list: `march_http_server_listen`).
2. For each call to a sharing builtin, identify the shared arguments.
3. Compute transitive closure of shared values (through closure captures and data structure fields) using the monomorphized type information.
4. Walk all `fn_def` bodies and upgrade RC ops on shared values to `RcAtomic`.
5. Handle interprocedural propagation: if a function parameter is shared at any call site, all RC ops on that parameter within the function body are upgraded.

**Deliverable:** HTTP server tests pass with correct atomic RC on the pipeline path. Actor tests pass with non-atomic RC on actor-local values.

### Phase 5: Remove HTTP Borrow Workaround (0.5 day)

Remove lines 668–688 from `march_http.c` (the manual `march_incrc` tree walk). Keep the single `march_incrc(pipeline)` at the top of `connection_thread` (needed because the C-level thread dispatch bypasses Perceus).

Alternatively, if Phase 4 is working correctly and the pipeline's RC is managed by Perceus-emitted code, verify that the single `march_incrc(pipeline)` in `connection_thread` is sufficient and remove the rest.

**Deliverable:** HTTP server works without manual borrow workaround. All HTTP tests and benchmarks pass.

### Phase 6: Benchmarking and Tuning (1 day)

Run the benchmark suite described above. Profile with `perf stat` for cache miss rates and branch misprediction. Tune the `IS_HEAP_PTR` guard (currently a branch on every RC call — consider branchless alternatives or link-time removal for known-pointer paths).

### Future: Inlined RC Operations

Once the mode system is stable, a further optimization: inline the non-atomic RC operations directly into LLVM IR instead of emitting a function call. For `RcLocal` mode:

```llvm
; Inline inc_rc_local for value %p
%rc_ptr = getelementptr i8, ptr %p, i64 0     ; rc is at offset 0
%old_rc = load i64, ptr %rc_ptr
%new_rc = add i64 %old_rc, 1
store i64 %new_rc, ptr %rc_ptr
```

This eliminates the function call overhead (argument passing, stack frame, return) for the hot path. The atomic variant should remain a function call (the `cmpxchg` loop is complex enough that inlining doesn't help and hurts code size).

### Future: Immortal Objects

For values that are known to live for the entire program lifetime (string literals, global constants, the HTTP pipeline closure itself), set RC to a sentinel value (e.g., `INT64_MAX`) that both `march_incrc` and `march_decrc` check and skip:

```c
#define MARCH_RC_IMMORTAL INT64_MAX

void march_incrc_local(void *p) {
    if (!IS_HEAP_PTR(p)) return;
    if (((march_hdr *)p)->rc == MARCH_RC_IMMORTAL) return;
    ((march_hdr *)p)->rc += 1;
}
```

This eliminates all RC traffic for immortal objects. The HTTP pipeline closure would be marked immortal at creation time, making the per-connection `march_incrc(pipeline)` call a no-op.

### Future: Per-Actor Arena Integration

When arenas are implemented, values allocated from an actor's arena can skip RC entirely (not just use non-atomic RC). The arena owns all its allocations, and actor death frees the entire arena. RC on arena-allocated values is redundant — the only purpose it serves is FBIP reuse detection, which can use a separate mechanism (e.g., a unique-ownership bit in the header).

## Summary of Changes

| Component | Change | Risk |
|---|---|---|
| `lib/tir/tir.ml` | Add `rc_mode` type; extend `EIncRC`, `EDecRC`, `EReuse` | Low — additive change |
| `lib/tir/perceus.ml` | Default all RC ops to `RcLocal` | Low — behavioral default same as before for single-thread |
| `lib/tir/rc_mode.ml` | New pass: thread-sharing analysis | Medium — must be correct to avoid data races |
| `lib/tir/llvm_emit.ml` | Dispatch on `rc_mode` for RC function calls | Low — mechanical |
| `lib/tir/pp.ml` | Print `rc_mode` in TIR pretty-printer | Low |
| `runtime/march_runtime.c` | Add `_local` variants of RC functions | Low — simple non-atomic versions |
| `runtime/march_http.c` | Remove manual borrow workaround | Medium — must verify correctness |
| `bin/main.ml` | Insert RC mode pass in pipeline | Low |

## Open Questions

1. **Granularity of sharing analysis.** The current design is coarse: if any call site passes a value to a thread-sharing function, all RC ops on that value (and its transitive closure) everywhere in the program become atomic. A more precise analysis could track per-call-site sharing, but the added complexity may not be worth it given that the shared set is typically small (one pipeline closure and its captures).

2. **`connection_thread` as March code.** The ideal end state is for the HTTP connection thread body to be compiled March code, not hand-written C. This requires the compiler to emit a function suitable for `pthread_create` (takes `void *`, returns `void *`). The connection thread would then be subject to Perceus analysis, and the manual `march_incrc(pipeline)` call would be replaced by compiler-inserted RC ops. This is a larger change to the HTTP runtime integration and is deferred.

3. **Mixed-mode FBIP.** If a value has `RcAtomic` mode, its `EReuse` must also be atomic (the `march_decrc_freed` check must be atomic). This is handled by propagating the mode to `EReuse`, but the interaction with FBIP detection (which currently doesn't consider modes) should be verified.

4. **Debug mode.** Consider a `-fatomic-rc-all` flag that forces all RC ops to atomic mode, useful for debugging data races. Conversely, a `-fno-atomic-rc` flag that forces all to non-atomic, useful for benchmarking the overhead delta.

5. **Dynamic mode switching.** An alternative to static analysis: store a flag in the object header indicating whether the object is shared. Check the flag at each RC operation. This is more flexible but adds a branch to every RC call (even non-atomic ones) and requires a mechanism to set the flag when an object crosses a thread boundary. Rejected for v1 in favor of static analysis, but worth revisiting if the static analysis proves too imprecise.

6. **Interaction with deferred cycle collector.** The cycle collector (if ever needed) runs per-actor on idle. It only touches actor-local values. Since actor-local values have `RcLocal` mode, the cycle collector never encounters atomic RC values. No interaction issues.
