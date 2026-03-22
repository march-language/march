# March Compiler & Runtime — Correctness Audit

**Date:** 2026-03-20
**Scope:** Full-stack analysis covering `march_runtime.c`, `llvm_emit.ml`, `typecheck.ml`, `perceus.ml`, `effects.ml`, and supporting modules.
**Methodology:** Static source review with line-level verification against the March codebase at HEAD.

---

## Summary

**20 issues identified** across the compiler and runtime, categorized by severity:

| Severity | Count | Fixed |
|----------|-------|-------|
| Critical | 3     | 3 ✅  |
| High     | 9     | 6 ✅  |
| Medium   | 5     | 2 ✅  |
| Quick Win| 3     | 3 ✅  |

**14 of 20 issues have been fixed** across four fix tracks (A–D). Critical issues affect memory safety in any multi-actor program. High issues represent semantic gaps where advertised language features are partially or wholly non-functional. Medium issues concern performance and scheduler behavior. Quick wins are low-effort fixes that close important gaps.

### Fix Track Summary

- **Track A: Type system fixes** (commit d8e4566) — Interface constraint discharge, linear type enforcement in patterns and closures. 12 new tests.
- **Track B: Codegen fixes** (commit 2c710f7) — Constructor name collision, arity mismatch now errors. 2 new tests.
- **Track C: Runtime/actor fixes** (committed, passed ThreadSanitizer) — Atomic RC, FBIP race fix, scheduler race fix, message RC double-increment fix, multi-message scheduling.
- **Track D: CAS wiring** (committed) — Content-addressed system wired into default compilation path. All 401+ tests pass.

---

## CRITICAL — Memory safety violations

### C1. FBIP RC data race in actor dispatch — ✅ FIXED (Track C, committed, passed ThreadSanitizer)

**File:** `runtime/march_runtime.c:297–302`
**Confirmed code:**
```c
/* FBIP: force rc=1 so handler can mutate actor in-place */
march_hdr *ahdr = (march_hdr *)actor;
int64_t saved_rc = atomic_load_explicit(&ahdr->rc, memory_order_relaxed);
atomic_store_explicit(&ahdr->rc, 1, memory_order_relaxed);
fn(closure, actor, msg);
atomic_store_explicit(&ahdr->rc, saved_rc, memory_order_relaxed);
```

**Problem:** The FBIP optimization temporarily forces the actor's reference count to 1 so the handler can mutate the actor state in-place. Both the load and store use `memory_order_relaxed`, providing no synchronization. While the handler executes, any concurrent thread calling `march_incrc` (line 24–27, also `memory_order_relaxed`) or `march_decrc` (lines 29–32, `memory_order_acq_rel`) on the same actor object will modify `rc` — but the stale `saved_rc` is blindly restored after the handler returns.

**Impact:** Every concurrent RC modification during handler execution is silently clobbered. In any multi-actor program where actors hold references to each other, this corrupts reference counts, leading to use-after-free (premature free from artificially low RC) or memory leaks (artificially high RC preventing collection).

**Reproduction:** Two actors A and B where B holds a reference to A. While A is processing a message (rc forced to 1), B sends a message that includes A as a payload — `march_send` calls `march_incrc(A)` on another thread. After A's handler returns, the saved RC overwrites the incremented value.

**Fix:** Either (a) use a per-actor lock or flag to prevent concurrent RC modification during FBIP dispatch, (b) use `atomic_compare_exchange` to restore only if RC hasn't changed, or (c) use a separate "FBIP active" flag that makes `incrc`/`decrc` defer their operations.

---

### C2. Constructor hashtable collision — type-unsafe codegen — ✅ FIXED (Track B, commit 2c710f7)

**File:** `lib/tir/llvm_emit.ml:1390–1394`
**Confirmed code:**
```ocaml
List.iteri (fun tag_idx (ctor_name, field_tys) ->
  Hashtbl.replace ctx.ctor_info ctor_name
    { ce_tag = tag_idx; ce_fields = field_tys };
  Hashtbl.replace ctx.poly_ctors (_name, ctor_name) field_tys
) ctors
```

**Problem:** Constructor metadata is stored in `ctx.ctor_info`, a flat hashtable keyed solely by the constructor name string. If two different types define constructors with the same name — which is perfectly legal in March's type system — `Hashtbl.replace` silently overwrites the first entry with the second. The surviving entry has different field counts and types.

**Impact:** Any subsequent allocation or pattern match on the shadowed constructor uses the wrong tag, wrong field count, and wrong field types. This produces LLVM IR that reads/writes beyond allocated memory, corrupting adjacent heap objects. The compiler emits no warning.

**Example:**
```
type Color = Red | Green | Blue
type Light = Red | Yellow | Green    // Red and Green collide
```
After processing `Light`, `ctx.ctor_info["Red"]` maps to `Light.Red` (tag 0, 0 fields) instead of `Color.Red` (tag 0, 0 fields — coincidentally safe here). But for constructors with different arities, e.g. `Node(left, right)` from two different tree types, the wrong field count is catastrophic.

**Fix:** Use type-qualified keys: `(type_name, ctor_name)` instead of bare `ctor_name`. The `poly_ctors` table already does this (line 1393), so the pattern exists. Alternatively, maintain per-type constructor tables.

---

### C3. Silent arity mismatch — falls back to `ptr` instead of erroring — ✅ FIXED (Track B, commit 2c710f7)

**File:** `lib/tir/llvm_emit.ml:909–910`
**Confirmed code:**
```ocaml
let field_ty = match List.nth_opt entry.ce_fields i with
  | Some t -> llvm_ty t | None -> "ptr" in
```

**Problem:** When emitting a heap allocation, the code iterates over the actual arguments and looks up the expected field type from `entry.ce_fields`. If the field index `i` exceeds the length of `ce_fields` (i.e., more arguments than the constructor metadata knows about), the code silently falls back to the generic `"ptr"` type instead of raising a compilation error.

**Impact:** This is the direct cascade from C2. When constructor collision produces wrong field counts, this fallback masks the mismatch and emits LLVM IR with incorrect struct layouts. Fields are stored at wrong offsets with wrong types, causing memory corruption at runtime. Even without C2, any future bug that produces mismatched arities will be silently swallowed here rather than caught at compile time.

**Fix:** Replace the `None -> "ptr"` fallback with a hard error:
```ocaml
| None -> failwith (Printf.sprintf
    "BUG: constructor field index %d out of range (expected %d fields)"
    i (List.length entry.ce_fields))
```

---

## HIGH — Semantic correctness gaps

### H1. Scheduler `scheduled` flag race — messages silently lost — ✅ FIXED (Track C, committed, passed ThreadSanitizer)

**File:** `runtime/march_runtime.c:387–393`
**Confirmed code:**
```c
if (!proc->scheduled) {
    proc->scheduled = 1;
    pthread_mutex_unlock(&proc->lock);
    enqueue_runnable(proc);
} else {
    pthread_mutex_unlock(&proc->lock);
}
```

**Context:** In `march_send()` (line 370+), after appending a message to the process mailbox, the code checks whether the process is already scheduled. The `scheduled` flag is protected by `proc->lock` at this call site. However, in the scheduler worker (line 311–318):

```c
// line 311-318: after processing
proc->processing = 0;
if (proc->mbox_head && proc->alive) {
    enqueue_runnable(proc);
} else {
    proc->scheduled = 0;  // line 315
    ...
}
```

**Problem:** There is a window between the worker checking `proc->mbox_head` (line 312) and setting `proc->scheduled = 0` (line 315) where a sender on another thread could enqueue a message and see `proc->scheduled == 1`, skipping the `enqueue_runnable` call. But the worker has already decided there's no more work and clears `scheduled`. The message sits in the mailbox with no worker to process it — it's lost until another message arrives to re-trigger scheduling.

**Impact:** Under concurrent sends, messages can be silently delayed indefinitely. In an actor system, this manifests as deadlocks or hangs where an actor stops responding despite having messages in its mailbox.

---

### H2. RC ABA problem — use-after-free on concurrent decrement — ✅ FIXED (Track C, committed, passed ThreadSanitizer)

RC operations are now fully atomic. `march_incrc` upgraded from non-atomic to proper atomic operations.

**File:** `runtime/march_runtime.c:29–32`
**Confirmed code:**
```c
void march_decrc(void *p) {
    if (!p) return;
    march_hdr *h = (march_hdr *)p;
    if (atomic_fetch_sub_explicit(&h->rc, 1, memory_order_acq_rel) <= 1) free(p);
}
```

**Also:** `march_incrc` at line 24–26 uses `memory_order_relaxed`.

**Problem:** Classic ABA scenario. Thread A calls `march_decrc`, sees `fetch_sub` return 1, is about to call `free(p)`. Thread B, racing, calls `march_incrc` on the same pointer (relaxed ordering — may not see A's decrement). Thread A frees the memory. Thread B now holds a dangling pointer. Alternatively, Thread B's increment may land on already-freed memory.

The root issue is that `march_incrc` uses `memory_order_relaxed` while `march_decrc` uses `memory_order_acq_rel`. The relaxed increment provides no ordering guarantee — it can be reordered before the decrement on another core, even after the object has been freed.

**Impact:** Use-after-free, double-free, or heap corruption in any multi-threaded program with shared references.

**Fix:** `march_incrc` should use at least `memory_order_acquire`, or the system should ensure that `incrc` is never called on an object that could concurrently reach RC=0 (e.g., via ownership discipline or hazard pointers).

---

### H3. Interface constraints completely ignored — ✅ FIXED (Track A, commit d8e4566)

`when Eq(a)` clauses are now actually checked. A `CInterface` constraint variant was added, emitted during instantiation of constrained polymorphic functions, and discharged by verifying that an `impl` exists for the concrete type.

**File:** `lib/typecheck/typecheck.ml` — constraint system (lines 93–106, 1557–1579)

**Confirmed code:** The constraint system only defines two variants:
```ocaml
type constraint_ =
  | CNum of ty
  | COrd of ty
```

And `discharge_constraints` (line 1560) only checks `CNum` and `COrd`:
```ocaml
let discharge_constraints env span =
  List.iter (fun c ->
      let ty, kind = match c with
        | CNum t -> (repr t, "Num")
        | COrd t -> (repr t, "Ord")
      in ...
```

**Problem:** There is no `CInterface` or `CClass` variant. When a function signature includes a constraint like `when Eq(a)`, the parser produces an AST node, and the interface definitions are registered (lines 1854–1862), but **no mechanism exists** to emit a constraint that says "type variable `a` must implement interface `Eq`." The `DImpl` handler (lines 1864–1898) validates that impl method types match the interface, but there is no pass that checks call sites against interface constraints.

**Impact:** Any function declared with `when Eq(a)` or similar interface bounds accepts *any* type at the call site, even types that don't implement the interface. This defeats the purpose of interfaces as a type-safety mechanism.

**Fix:** Add a `CInterface of string * ty` constraint variant, emit it during instantiation of constrained polymorphic functions, and discharge it by verifying that an `impl` exists for the concrete type.

---

### H4. Linear types broken through patterns — ✅ FIXED (Track A, commit d8e4566)

`infer_pattern` now propagates `TLin` qualifier to pattern-bound variables, so destructuring a linear value preserves linearity on the resulting bindings.

**File:** `lib/typecheck/typecheck.ml` — `infer_pattern` (line 919+)

**Confirmed code:** `infer_pattern` returns `(string * scheme) list * ty` — a flat list of `(name, scheme)` bindings. It does not propagate linearity information:

```ocaml
let rec infer_pattern env (pat : Ast.pattern)
    : (string * scheme) list * ty =
```

At the call site (e.g., line 1317–1319 in match arms):
```ocaml
let bindings, pat_ty = infer_pattern env br.branch_pat in
...
let env' = bind_vars bindings env in
```

`bind_vars` creates normal unrestricted bindings. The `bind_linear` function (line 294) is only used for function parameters (lines 1440, 1482).

**Problem:** When a linear value is destructured via a pattern match, the resulting bindings lose their linearity. A `linear Pair(a, b)` matched as `Pair(x, y)` produces unrestricted `x` and `y` — both can be freely duplicated or dropped, violating the linearity guarantee.

**Impact:** The linear type system is unsound for any program that pattern-matches on linear values, which is virtually every program using linear types.

---

### H5. Linear types broken through closures — ✅ FIXED (Track A, commit d8e4566)

Captures of linear values are now tracked. When a closure captures a linear variable from an enclosing scope, the capture is recorded as consuming the variable in the outer scope.

**File:** `lib/typecheck/typecheck.ml` — closure/lambda inference

**Problem:** The linearity checker tracks linear variables through mutable `bool ref` flags in `lin_entry` records (line 242–243). When a closure captures a linear variable from an enclosing scope, there is no mechanism to:
1. Record that the capture occurred (transferring ownership into the closure)
2. Prevent the closure from being called multiple times (which would use the linear value multiple times)
3. Mark the captured variable as consumed in the enclosing scope

The `check_linear_all_consumed` function (line 897) only checks variables bound in the *current* function's parameter list (line 1529–1533), not captures.

**Impact:** A linear value can be captured by a closure and used multiple times if the closure is called multiple times. The outer scope may also continue using the value, resulting in double-use of a linear resource.

---

### H6. Linear types broken through record fields

**Problem:** The `bind_linear` call (lines 1440, 1482) only fires for function parameters with non-`Unrestricted` linearity:
```ocaml
| lin -> bind_linear p.param_name.txt lin t env
```

When a linear value is stored in a record field, tuple element, or constructor argument, the resulting composite value is not tracked as linear. Fields can be independently extracted and used multiple times without triggering linearity errors.

**Impact:** Combined with H4 and H5, the entire linear/affine type system is effectively advisory — it catches trivial double-uses of directly-bound variables but misses structural cases.

---

### H7. Message RC double-increment — every message leaks — ✅ FIXED (Track C, committed, passed ThreadSanitizer)

`march_send` no longer double-increments message RC. The ownership semantics between Perceus and `march_send` have been resolved.

**File:** `runtime/march_runtime.c:378` and `lib/tir/perceus.ml`

**Confirmed code in `march_send`:**
```c
march_incrc(msg);  // line 378
```

**Problem:** The Perceus RC analysis (Phase 4 in `perceus.ml`) inserts `EIncRC` for every argument that is still live after a function call. When a value is passed to `march_send()`, Perceus inserts an increment because the value continues to be live (it's being sent, not consumed). But `march_send` itself *also* increments the message's RC (line 378) because it's taking shared ownership for the mailbox.

**Impact:** Every sent message has its RC incremented twice but only decremented once (by the receiver). This is a systematic memory leak — every message sent between actors leaks its payload. In a long-running actor system, this constitutes unbounded memory growth.

**Fix:** Either (a) remove the `march_incrc(msg)` in `march_send` and rely on Perceus to handle the ownership transfer, or (b) teach Perceus that `march_send` is a consuming operation that takes ownership (like `free`), so it should not insert an increment for the argument.

---

### H8. Session types are dead code

**File:** `lib/typecheck/typecheck.ml:270, 277, 1840–1848`

**Confirmed:** `protocols` appears exactly 4 times in `typecheck.ml`:
1. **Line 270:** Field declaration — `protocols : (string * Ast.protocol_def) list`
2. **Line 277:** Initialization — `protocols = []`
3. **Line 1842:** Duplicate check — `List.mem_assoc name.txt env.protocols`
4. **Line 1848:** Registration — `{ env with protocols = (name.txt, pdef) :: env.protocols }`

**Problem:** Protocol definitions are parsed (the AST supports `ProtoMsg`, `ProtoLoop`, `ProtoChoice` in `lib/ast/ast.ml:227–236`) and stored in the type environment, but no code ever *reads* from `env.protocols` to validate anything. There is no:
- Channel type checking against protocol steps
- Send/receive type validation
- Protocol conformance verification
- Session type progression tracking

**Impact:** `protocol` declarations are accepted syntactically but provide zero type safety. Programs can send messages of the wrong type, skip protocol steps, or violate branching constraints with no compiler error.

---

### H9. Effects/capability system is a stub

**File:** `lib/effects/effects.ml` (entire file, 9 lines)

**Confirmed code:**
```ocaml
(** March capability system — stub.
    Tracks capability types for FFI safety and actor messaging.
    Replaces the previous effect system. *)

let check_capabilities (_m : March_ast.Ast.module_) =
  (* TODO: Implement *)
  ()
```

**Context:** The type system registers capability builtins (`Cap(IO)`, `Cap(IO.Console)`, etc.) and `DNeeds` declarations specify required capabilities. But the `check_capabilities` function — the only entry point for the effects system — is a no-op.

**Impact:** `needs IO.Network` declarations are accepted but never enforced. Any function can perform any side effect regardless of its declared capabilities. The capability system provides a false sense of security.

---

## MEDIUM — Performance and scheduler issues

### M1. Scheduler processes one message per queue cycle — ✅ FIXED (Track C, committed, passed ThreadSanitizer)

**File:** `runtime/march_runtime.c:288–314`

**Problem:** The scheduler worker dequeued one message node from the process mailbox per scheduling round, causing excessive queue management overhead.

**Resolution:** The scheduler now processes multiple messages per cycle, reducing global lock acquisition overhead and fixing the starvation issue where a single busy actor with many queued messages would monopolize the lock.

---

### M2. No preemption mechanism

**File:** `runtime/march_runtime.c` — scheduler worker (lines 260–321)

**Problem:** Once a handler function `fn(closure, actor, msg)` is called (line 301), there is no mechanism to interrupt it. A long-running or infinite-loop handler blocks its scheduler thread indefinitely. With 4 scheduler threads (default), 4 stuck actors starve the entire system.

**Note:** The OCaml-level scheduler in `lib/scheduler/scheduler.ml` has a cooperative preemption mechanism with reduction counting (max 4000 per quantum), but this is for the compiler's own scheduling model and is not connected to the C runtime's thread pool.

---

### M3. No work stealing in the C runtime

**File:** `runtime/march_runtime.c:231–241`

**Problem:** The C runtime uses a single global run queue protected by a mutex. The OCaml-level scheduler has a Chase-Lev work-stealing deque implementation (`lib/scheduler/work_pool.ml`), but this is not connected to the C runtime.

**Impact:** All scheduler threads contend on a single mutex. Under high actor counts, this becomes a bottleneck. Work stealing would allow threads to maintain local queues and only steal when idle, reducing contention.

---

### M4. `march_incrc` uses `memory_order_relaxed` — ✅ FIXED (Track C, committed, passed ThreadSanitizer)

**File:** `runtime/march_runtime.c:26`

**Resolution:** RC operations are now fully atomic with proper memory ordering. This was fixed as part of the broader atomic RC work in Track C, which also addressed C1 and H2.

---

### M5. `march_decrc` check uses `<= 1` instead of `== 1`

**File:** `runtime/march_runtime.c:32`

```c
if (atomic_fetch_sub_explicit(&h->rc, 1, memory_order_acq_rel) <= 1) free(p);
```

**Problem:** `atomic_fetch_sub` returns the *previous* value. If RC was 1, the new value is 0, and freeing is correct. But `<= 1` also triggers if the previous value was 0 or negative, which indicates a double-decrement bug. Rather than catching this corruption, the code silently frees (potentially double-frees) the object.

**Impact:** Masks RC underflow bugs. Should be `== 1` with an assertion or error log for `< 1`.

---

## QUICK WINS — High-impact, low-effort fixes

### Q1. CAS system is 95% built — ✅ FIXED (Track D, committed)

CAS now wired into the default compilation path in `driver.ml`. All 401+ tests pass.

---

### Q2. Type-qualified constructor keys — ✅ FIXED (Track B, commit 2c710f7)

Constructors now stored as `"TypeName.CtorName"` in both TIR `lower.ml` and `llvm_emit.ml`, eliminating the collision risk.

---

### Q3. Interface constraint discharge pass — ✅ FIXED (Track A, commit d8e4566)

`CInterface` constraint variant added to `constraint_` type. Interface constraints are now emitted during instantiation and discharged by verifying impl existence. 12 new tests added covering interface constraint checking.

---

## File Reference Index

| File | Path | Lines | Issues |
|------|------|-------|--------|
| `march_runtime.c` | `runtime/march_runtime.c` | 880 | C1, H1, H2, H7, M1–M5 |
| `llvm_emit.ml` | `lib/tir/llvm_emit.ml` | 1659 | C2, C3, Q2 |
| `typecheck.ml` | `lib/typecheck/typecheck.ml` | 2006 | H3, H4, H5, H6, H8, H9, Q3 |
| `perceus.ml` | `lib/tir/perceus.ml` | 498 | H7 |
| `effects.ml` | `lib/effects/effects.ml` | 9 | H9 |
| `ast.ml` | `lib/ast/ast.ml` | 306 | H8 (protocol AST) |
| `scheduler.ml` | `lib/scheduler/scheduler.ml` | 72 | M2 (OCaml scheduler) |
| `work_pool.ml` | `lib/scheduler/work_pool.ml` | 109 | M3 (unused in C runtime) |

---

## Recommended Priority Order

~~1. **C1 + Q1** — Fix the FBIP RC data race.~~ ✅ DONE (Track C + D)
~~2. **C2 + Q2** — Type-qualify constructor keys.~~ ✅ DONE (Track B)
~~3. **C3** — Hard-error on arity mismatch.~~ ✅ DONE (Track B)
~~4. **H2** — Strengthen `march_incrc` memory ordering.~~ ✅ DONE (Track C)
~~5. **H1** — Fix the scheduler race.~~ ✅ DONE (Track C)
~~6. **H7** — Resolve the double-increment ownership semantics.~~ ✅ DONE (Track C)
~~7. **H3 + Q3** — Wire up interface constraint checking.~~ ✅ DONE (Track A)
~~8. **H4–H5** — Linear type soundness in patterns and closures.~~ ✅ DONE (Track A)

### Remaining Priority Order

1. **H6** — Linear types broken through record fields. Requires design decisions about structural linearity.
2. **H8–H9** — Session types and effects are feature completions, not correctness regressions.
3. **M2, M3, M5** — Remaining performance improvements (preemption, work stealing, decrc check), schedulable independently.
