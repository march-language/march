# March Escape Analysis — Design Spec

## Overview

Escape Analysis (Pass 5) stack-promotes heap allocations whose lifetimes are
provably bounded to the current function's stack frame. An `EAlloc` that does
not escape is replaced with `EStackAlloc`, eliminating the allocator call.

After this pass:
- `EAlloc` nodes remain for values that escape (heap-allocated at runtime).
- `EAlloc` nodes for non-escaping values are replaced with `EStackAlloc`.
- `EDecRC`/`EFree` operations on stack-allocated variables are removed
  (stack variables are freed when the frame is popped — no RC needed).

## Position in the Pipeline

```
Lower → Mono → Defun → Perceus RC → Escape → LLVM emit
```

Input: a Perceus-annotated `tir_module` (may contain `EIncRC`, `EDecRC`,
`EFree`, `EReuse` nodes).
Output: same structure with some `EAlloc` nodes replaced by `EStackAlloc`,
and dead RC ops on stack-allocated variables removed.

## TIR Change

Add one new expression constructor to `tir.ml`:

```ocaml
| EStackAlloc of ty * atom list
(* stack allocation — inserted by Escape analysis.
   Same semantics as EAlloc but the object lives on the call stack. *)
```

`pp.ml` gets a corresponding case:
```ocaml
| EStackAlloc (ty, args) ->
  "stack_alloc " ^ string_of_ty ty ^
  "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
```

No other TIR types change. All existing passes that pattern-match `expr` need
an additional arm for `EStackAlloc`; the conservative default is to treat it
like `EAlloc` (recurse into args).

---

## Key Definitions

### Escaping vs. Non-Escaping

A variable `v` bound to an allocation **escapes** the current function if its
value can be observed or reachable after the function returns. In TIR ANF form,
`v` escapes if it appears in any of these positions:

| Position | Reason |
|---|---|
| `EAtom (AVar v)` in tail position | Returned to caller |
| `EApp (_, args)` where `AVar v ∈ args` | Passed to callee; callee may store it |
| `ECallPtr (_, args)` where `AVar v ∈ args` | Same |
| `EApp (v_as_fn, _)` where `v = v_as_fn` | Used as a function to call (closure) |
| `EAlloc (_, args)` where `AVar v ∈ args` | Stored into a heap constructor |
| `ERecord fields` where `AVar v` is a field value | Stored in a record |
| `EUpdate (_, fields)` where `AVar v` is a field value | Stored in a functional update |
| `ETuple atoms` where `AVar v ∈ atoms` | Stored in a tuple |
| `EReuse (_, _, args)` where `AVar v ∈ args` | Stored via FBIP reuse |

`v` does **not** escape if it appears only in:

| Position | Reason |
|---|---|
| `ECase (AVar v, ...)` scrutinee | Pattern match — destructs it locally |
| `EField (AVar v, _)` | Field projection — read-only, no store |
| `EIncRC (AVar v)` | RC management — no store |
| `EDecRC (AVar v)` | RC management — no store |
| `EFree (AVar v)` | Dealloc — no store |
| `EReuse (AVar v, _, _)` **first** position | The *reuse token* position — v is being freed/reused, not stored |

### Single-Ownership Requirement

Stack promotion is only valid when `v` has exactly one owner at all points —
i.e., no `EIncRC (AVar v)` appears in the function body after binding. If
Perceus inserted an `EIncRC` for `v`, there are multiple live references to
the same allocation, and stack promotion would create a dangling reference.

**Condition**: `v` is stack-promotable iff:
1. `v` is bound to `EAlloc` (not `ECallPtr` result, not a parameter).
2. `v` does not appear in any escaping position (table above).
3. No `EIncRC (AVar v)` appears anywhere in the function body.

Condition 3 is automatically satisfied when `v` is not live at any non-last
use — but we check it explicitly for safety.

---

## Algorithm

Escape analysis is **per-function, intra-procedural**. Same scope rationale as
Perceus: actor isolation + ownership convention makes this sufficient.

### Phase 1 — Collect Allocation Candidates

Walk the `fn_def` body. For each `ELet(v, EAlloc(ty, args), body)`, record
`v` as an allocation candidate: `candidates : StringSet.t`.

### Phase 2 — Escape Check

Walk the `fn_def` body. For each candidate variable `v`, determine whether it
escapes by checking all uses.

```ocaml
(* Returns the subset of [candidates] that escape in [e]. *)
val escaping_vars : expr -> StringSet.t -> StringSet.t
```

The walk is a simple fold over all sub-expressions, collecting variables that
appear in escaping positions. The result is the set of candidates that escape.

**Stack-promotable set**: `promotable = candidates \ escaping_vars(body, candidates)`.

Then further filter: remove any `v ∈ promotable` for which `EIncRC (AVar v)`
appears anywhere in the body.

### Phase 3 — Transform

Walk the `fn_def` body and apply two rewrites:

**Rewrite A** — Promote allocation:
```
ELet(v, EAlloc(ty, args), body)   where v ∈ promotable
→ ELet(v, EStackAlloc(ty, args), body)
```

**Rewrite B** — Remove dead RC ops on stack variables:
```
EDecRC (AVar v)   where v ∈ promotable  →  EAtom (ALit LitUnit)
EFree  (AVar v)   where v ∈ promotable  →  EAtom (ALit LitUnit)
```

`EDecRC`/`EFree` for stack-promoted vars were inserted by Perceus for dead
bindings (unused allocations). Since the stack frame handles deallocation, these
ops are now no-ops. We replace them with `EAtom(ALit LitUnit)` (a no-op
expression in a `ESeq` context); the LLVM emit pass will skip unit atoms in
sequence position.

Alternatively, if the `EDecRC` appears as `ESeq(EDecRC(AVar v), rest)` where
`v ∈ promotable`, simplify to `rest` directly.

### Entry Point

```ocaml
val escape_analysis : Tir.tir_module -> Tir.tir_module
(* Runs all three phases over every fn_def in tm_fns. *)
```

---

## Worked Examples

### Example 1 — Local constructor, only matched

```march
fn sum_pair(p : Pair(Int, Int)) : Int do
  match p with
  | Pair(a, b) -> a + b
  end
end
```

Post-defun TIR (simplified):
```
fn sum_pair(p : Pair(Int, Int)) : Int =
  case p of
    Pair(a, b) -> let $t = a + b in $t
```

`p` is a parameter (not an `EAlloc`), so escape analysis doesn't apply here.

---

### Example 2 — Local allocation, only matched (stack-promotable)

```march
fn make_and_match(x : Int) : Int do
  let p = Pair(x, x)
  match p with
  | Pair(a, b) -> a + b
  end
end
```

Post-Perceus TIR (simplified):
```
fn make_and_match(x : Int) : Int =
  let p = alloc Pair(AVar x, AVar x) in
  case p of
    Pair(a, b) -> let $t = a + b in $t
```

Escape check for `p`:
- `p` appears as `ECase(AVar p, ...)` scrutinee — **non-escaping**.
- No `EIncRC(AVar p)`.

`p` is stack-promotable. After Escape:
```
fn make_and_match(x : Int) : Int =
  let p = stack_alloc Pair(AVar x, AVar x) in
  case p of
    Pair(a, b) -> let $t = a + b in $t
```

At LLVM emit: `p` becomes an `alloca`, loaded before the case.

---

### Example 3 — Allocation returned (NOT promotable)

```march
fn wrap(x : Int) : Box(Int) do Box(x) end
```

Post-Perceus TIR:
```
fn wrap(x : Int) : Box(Int) =
  let b = alloc Box(AVar x) in
  EAtom(AVar b)   (* tail return *)
```

Escape check for `b`:
- `b` appears as `EAtom(AVar b)` in tail position — **escapes**.

`b` is NOT stack-promotable. `EAlloc` remains.

---

### Example 4 — Allocation stored into another heap value (NOT promotable)

```march
fn nest(x : Int) : Outer(Inner(Int)) do
  let inner = Inner(x)
  Outer(inner)
end
```

Post-Perceus TIR:
```
fn nest(x : Int) =
  let inner = alloc Inner(AVar x) in
  let outer = alloc Outer(AVar inner) in
  EAtom(AVar outer)
```

Escape check for `inner`:
- `inner` appears as arg to `EAlloc(Outer, [AVar inner])` — **escapes**.

`inner` is NOT stack-promotable.

---

### Example 5 — Dead allocation (immediately freed by Perceus)

```march
fn discard(x : Int) : Int do
  let _ = Box(x)
  42
end
```

Post-Perceus TIR:
```
fn discard(x : Int) : Int =
  let b = alloc Box(AVar x) in
  ESeq(EDecRC(AVar b), EAtom(ALit 42))
```

Escape check for `b`:
- `b` appears only as `EDecRC(AVar b)` — **non-escaping**.
- No `EIncRC(AVar b)`.

`b` is stack-promotable. After Escape:
```
fn discard(x : Int) : Int =
  let b = stack_alloc Box(AVar x) in
  ESeq(EAtom(ALit LitUnit), EAtom(ALit 42))
  -- simplified to: EAtom(ALit 42)
```

The `EDecRC` was the only user of `b`; after removal, the `stack_alloc` itself
becomes dead. LLVM will DCE it (or emit a trivial `alloca` that's immediately
discarded).

---

## Interaction with Perceus

Perceus runs before Escape. This means:
- `EIncRC`/`EDecRC` nodes are already present when Escape runs.
- The single-ownership check (no `EIncRC` for `v`) uses these existing nodes.
- Dead-binding `EDecRC` nodes on stack-promoted variables are cleaned up in
  Phase 3 (Rewrite B).
- `EReuse` nodes: the *reuse token* (`dec_v` in `EReuse(AVar dec_v, ty, args)`)
  is being freed — treat as non-escaping for the `dec_v` position. The result
  variable of a `EReuse` does escape if it's returned or stored (checked
  normally).

**Order sensitivity**: Running Escape before Perceus would be incorrect —
Perceus inserts `EIncRC` which the single-ownership check relies on.

---

## Interaction with LLVM Emit

LLVM emit (Pass 6) sees `EStackAlloc` nodes and lowers them to:
```llvm
%v = alloca <ty>
; fill in fields at the alloca address
```

`EAlloc` nodes are lowered to heap allocation:
```llvm
%v = call ptr @march_alloc(i64 <size>)
; fill in tag + fields
```

The distinction is purely in the alloc call: `alloca` vs `@march_alloc`.

For `EStackAlloc` scrutinees in `ECase`: the case is pattern-matching a stack
struct. LLVM reads the tag field from the alloca'd memory, or (post-optimization)
the tag is a compile-time constant and the case is eliminated.

---

## Scope Limitations and Simplifications (v1)

1. **No alias tracking.** If `let u = v` (rebinding) and `u` escapes, `v`
   transitively escapes. The current algorithm checks uses of `v` directly.
   In well-typed ANF, rebinding is rare (the type checker generates fresh
   bindings), but if it occurs, `v` might be missed as escaping via `u`.
   For safety: treat `ELet(u, EAtom(AVar v), body)` as making `v` escape if
   `u` escapes. (Not currently in scope for v1 — rebinding is uncommon in
   generated ANF.)

2. **No cross-function stack promotion.** An `EAlloc` returned from a callee
   and assigned to `v` in the current function cannot be stack-promoted (it
   was already heap-allocated by the callee). Only allocations created in the
   current function are candidates.

3. **ERecord / ETuple conservatively escape.** Values stored into records or
   tuples are treated as escaping even though the record/tuple itself may be
   stack-allocated. This is correct (safe) but may miss opportunities.

4. **No loop-carried analysis.** `ELetRec` bodies (genuine mutual recursion,
   rare post-defun) are not analyzed for escape — their free variables are
   conservatively assumed to escape.

5. **`$Clo_` structs are closure captures.** Closure structs are created by
   the defun pass and immediately returned (closure creation site returns the
   struct). They always escape. The escape check handles this naturally:
   the `EAlloc(TCon("$Clo_...", []), fv_atoms)` result is returned, so it escapes.

---

## Implementation Structure

```
lib/tir/escape.ml
```

```ocaml
module StringSet = Set.Make (String)

(* Phase 1 *)
val collect_alloc_candidates : Tir.expr -> StringSet.t

(* Phase 2 *)
val escaping_vars : Tir.expr -> StringSet.t -> StringSet.t
val has_incrc_for : Tir.expr -> StringSet.t -> StringSet.t
(* Returns subset of candidates that have EIncRC inserted by Perceus *)

(* Phase 3 *)
val promote_expr : Tir.expr -> StringSet.t (* promotable *) -> Tir.expr

(* Per-function entry *)
val escape_fn : Tir.fn_def -> Tir.fn_def

(* Module entry point *)
val escape_analysis : Tir.tir_module -> Tir.tir_module
```

### dune

Add `escape` to the `march_tir` library modules:
```
(modules tir pp lower mono defun perceus escape)
```

### bin/main.ml

After Perceus:
```ocaml
let tir = March_tir.Perceus.perceus tir in
let tir = March_tir.Escape.escape_analysis tir in
```

### tir.ml / pp.ml

Add `EStackAlloc` to `expr` and its `pp` case. All passes that match `expr`
need a new arm; the safe default for existing passes is:
```ocaml
| Tir.EStackAlloc (_, args) ->
  List.fold_left (fun acc a -> StringSet.union acc (vars_of_atom a)) acc args
```
(treat like EAlloc for liveness, free-variable, and rewriting purposes).

---

## Open Questions

1. **Stack size limits.** Large stack allocations can overflow the stack for
   deeply recursive functions. A size heuristic (e.g., only promote allocations
   ≤ 4 fields) would bound stack usage. For v1, promote any non-escaping
   allocation without size limit.

2. **Interaction with `EReuse`.** An `EReuse(AVar dec_v, ty, args)` reuses
   `dec_v`'s memory in-place. If the `EReuse` result is then stack-promotable
   (i.e., the result doesn't escape), we should replace the `EReuse` with
   `EStackAlloc` and simply drop the `dec_v` reference entirely. This would
   require re-running Escape after FBIP, or handling it in a combined pass.

3. **Alias via `EField`.** `EField(AVar v, name)` projects a field of `v`.
   If the projected value is itself an allocation that was stored in `v`, and
   that inner allocation escapes via `EField`, it does so through `v`. The
   current algorithm doesn't track field-level escape; `v` itself is treated
   as non-escaping if only projected. This is correct because we're tracking
   whether the *allocation of v* escapes, not the allocations stored inside `v`.

4. **`EUpdate` semantics.** `EUpdate(AVar v, fields)` creates a new record
   by copying `v` with updated fields. The result is a new allocation. If `v`
   is stack-allocated and we're creating an updated copy, the copy should be
   heap-allocated (it may escape) while the original stack allocation is freed
   normally. This is handled correctly by the current design: `EUpdate` args
   are treated as escaping (the values stored in the new copy may escape), but
   the `v` (the base record) is only the *source* of the copy. Whether `v`
   escapes depends on whether it appears as an arg to `EUpdate` fields — it
   does not (it's the base, not a field value). So `v` may still be
   stack-promoted. Correct.
