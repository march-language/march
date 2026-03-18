# March Perceus RC Analysis — Design Spec

## Overview

Perceus RC Analysis (Pass 4) inserts reference-counting operations into the TIR,
exploiting static last-use information to elide as many RC operations as possible.
It also detects FBIP (Functional But In-Place) reuse opportunities.

After this pass:
- Every heap-allocated unrestricted (`Unr`) value has explicit `EIncRC`/`EDecRC`
  at the minimal set of points required for correctness
- Linear (`Lin`) and affine (`Aff`) values get `EFree` at their last use instead
  of RC operations (the type system guarantees uniqueness; no counting needed)
- `EAlloc` + coincident `EDecRC` pairs of the same constructor shape become `EReuse`

## Position in the Pipeline

```
Lower → Mono → Defun → Perceus RC → Escape → LLVM emit
```

Input: a defunctionalized `tir_module` (no `ELetRec`-lambdas, no closure-typed `EApp`).
Output: same structure with `EIncRC`, `EDecRC`, `EFree`, and `EReuse` nodes inserted.

## Key Invariant: Ownership

Every heap value has exactly one *owner* at any program point.

- **Function parameters**: callee receives ownership (the caller either transferred
  its last reference or incremented before the call).
- **`ELet` bindings**: the bound variable owns the value (RHS produces rc=1).
- **`EApp` result**: the caller owns the returned value.
- **Last use**: owner is released — RC decremented, or value freed if linear.
- **Non-last use**: owner must duplicate the reference — `EIncRC` before the use
  so the owner retains its copy.

The principle: no RC adjustment is needed when transferring ownership (last use).
Perceus exploits this to the maximum extent statically determinable.

## Scope: Per-Function, Intra-Procedural

The analysis is local to each `fn_def`. This is sufficient because:
- Actor isolation: no cross-actor aliasing is possible by construction
- Ownership convention: every call site either transfers or duplicates before calling
- The interprocedural effect is fully captured by the calling convention above

No interprocedural analysis, no alias analysis, no global escape tracking.

---

## Algorithm

### Phase 1 — Backwards Liveness Analysis

Compute, for each expression node in a `fn_def` body, the set of variables that are
*live after* that node (i.e., used again on at least one path to the function exit).

Liveness equations (standard backwards dataflow, ANF form):

```
live_before(EAtom (AVar v), live_after)
  = live_after ∪ {v}

live_before(EAtom (ALit _), live_after)
  = live_after

live_before(EApp (f, args), live_after)
  = live_after ∪ {f} ∪ {v | AVar v ∈ args}

live_before(ECallPtr (a, args), live_after)
  = live_after ∪ vars(a) ∪ {v | AVar v ∈ args}

live_before(ELet (v, e1, e2), live_after)
  let l2 = live_before(e2, live_after)
  let l1 = live_before(e1, l2 \ {v})
  = l1

live_before(ECase (a, branches, default), live_after)
  let arm_lives = [live_before(br.br_body, live_after \ {v | v ∈ br.br_vars})
                   | br ∈ branches]
                 ++ [live_before(def, live_after) | Some def]
  = vars(a) ∪ ⋃ arm_lives

live_before(ESeq (e1, e2), live_after)
  let l2 = live_before(e2, live_after)
  = live_before(e1, l2)

live_before(ETuple atoms, live_after)
  = live_after ∪ ⋃ vars(atoms)

(ERecord, EField, EUpdate, EAlloc, EFree, EIncRC, EDecRC, EReuse, ECallPtr
 — standard: live_after ∪ free vars of all atoms in those expressions)
```

**Last-use detection**: a use of variable `v` at expression `e` is the *last use*
iff `v ∉ live_after(e)`.

### Phase 2 — RC Insertion

Walk each `fn_def` body top-down, threading liveness information (computed in
Phase 1) to determine, at each use, whether it is last.

**Rule 1 — Non-last use of an `Unr` variable:**
Whenever `AVar v` appears in an atom position and `v ∈ live_after`:
```
before: ... use AVar v ...
after:  ESeq (EIncRC (AVar v), ... use AVar v ...)
```
Insert `EIncRC` immediately before the use. The callee/consumer receives ownership;
the caller retains its copy (which it will release at its own last use).

**Rule 2 — Last use of an `Unr` variable (not at a tail position):**
Whenever `AVar v` appears and `v ∉ live_after`, and this is NOT a direct transfer
into a function call arg (see Rule 3):
```
before: EAtom (AVar v)   (* v returned, last use *)
after:  EAtom (AVar v)   (* no change — v's ownership transfers to caller *)
```
No operation needed — ownership is transferred to the function's caller or the
enclosing `ELet` binding.

**Rule 3 — Last use of an `Unr` variable in `EApp`/`ECallPtr` arg position:**
If `AVar v` is an argument to a call AND `v ∉ live_after`:
- No `EIncRC` needed: ownership is transferred to the callee.

If `AVar v` is an argument to a call AND `v ∈ live_after`:
- Insert `EIncRC (AVar v)` before the `EApp`/`ECallPtr`.
- Callee receives a duplicated reference; caller retains original.

**Rule 4 — Dead binding (variable bound but never used):**
If `v` is bound by `ELet (v, e1, e2)` but `v ∉ live_before(e2, live_after)`:
```
before: ELet (v, e1, e2)
after:  ELet (v, e1, ESeq (EDecRC (AVar v), e2))   (* Unr *)
        ELet (v, e1, ESeq (EFree (AVar v), e2))    (* Lin/Aff *)
```
Insert a dec/free at the start of `e2` to release the unused owned reference.

**Rule 5 — Linear/affine last use:**
Whenever `AVar v` appears with `v.v_lin = Lin || v.v_lin = Aff` and `v ∉ live_after`:
Insert `EFree (AVar v)` immediately after the last use.
```
before: ELet (result, EApp (f, [AVar v]), rest)   (* v last used here *)
after:  ELet (result, EApp (f, [AVar v]), ESeq (EFree (AVar v), rest))
```
Note: for Lin/Aff, NO `EIncRC` is ever inserted on non-last uses — the type
checker already guarantees uniqueness, so non-last uses of a linear value are
a type error and should not appear in a well-typed program.

### Phase 3 — RC Elision

After insertion, scan for adjacent cancel pairs on the same control-flow path:

```
ESeq (EIncRC (AVar v), ESeq (EDecRC (AVar v), rest))
→ rest
```

This occurs at function call boundaries: the caller inserts `EIncRC` (non-last use),
the callee's parameter is immediately the last use so it inserts `EDecRC`. Since
ANF makes this pattern explicit and local, the cancellation is a simple peephole.

More precisely: after the full module is processed, a second pass over each
`fn_def` body eliminates any `EIncRC`/`EDecRC` pairs for the same variable `v`
that appear sequentially with no intervening use or branch.

### Phase 4 — FBIP Detection

After RC insertion and elision, scan each `fn_def` for the pattern:

```
ELet (_, EDecRC (AVar v), ELet (result, EAlloc (ty, args), rest))
  where shape(v.v_ty) = shape(ty)
```

Replace with:

```
ELet (result, EReuse (AVar v, ty, args), rest)
```

**Shape compatibility**: `shape(TCon(n, ts)) = shape(TCon(n, ts'))` iff `n` is the
same constructor name AND `List.length ts = List.length ts'`. Field types need not
match (different monomorphizations of the same constructor can share memory if the
total field count is equal and all fields are pointer-sized — this is a simplification;
see Open Questions).

**Why this is correct**: `EDecRC (AVar v)` at this point means `v`'s reference count
hit 0 (the caller had the last reference). The memory at `v`'s address is available
for reuse. `EReuse` instructs the runtime to skip the allocator and overwrite `v`'s
memory in-place with the new constructor. From the language's perspective this is
still a pure functional operation — the old value is gone, the new value is fresh.

---

## Worked Examples

### Example 1 — Simple ownership transfer (no RC ops)

```march
fn double_list(xs : List(Int)) : List(Int) do
  match xs with
  | Nil -> Nil()
  | Cons(head, tail) -> Cons(head * 2, double_list(tail))
  end
end
```

TIR body (simplified, post-defun):
```
case xs of
  Nil()        -> alloc Cons()
  Cons(h, tl) -> let h2 = h * 2 in
                 let rest = double_list(AVar tl) in
                 alloc Cons(AVar h2, AVar rest)
```

Liveness: In the `Cons` arm:
- `h` is last-used at `h * 2` — ownership transfer to the multiply result
- `tl` is last-used in the `double_list` call — ownership transfer to callee
- `xs` is last-used at the `case` scrutinee

After Perceus: **no RC operations inserted** — all uses are last uses, ownership
transfers naturally throughout.

### Example 2 — Non-last use requires `EIncRC`

```march
fn pair_it(x : Int) : (List(Int), Int) do
  let xs = Cons(x, Nil())
  (xs, length(xs))     -- xs used twice: once in tuple, once in length
end
```

TIR body (post-defun, simplified):
```
let xs = alloc Cons(AVar x, alloc Nil()) in
let len = length(AVar xs) in
(AVar xs, AVar len)
```

Liveness:
- At `length(AVar xs)`: `xs ∈ live_after` (used again in tuple) → non-last use
- At `(AVar xs, AVar len)`: `xs ∉ live_after` → last use

After Perceus:
```
let xs = alloc Cons(AVar x, alloc Nil()) in
EIncRC (AVar xs);                        (* Rule 1: non-last use *)
let len = length(AVar xs) in
(AVar xs, AVar len)                      (* last use: ownership to caller *)
```

### Example 3 — FBIP reuse (map over list)

```march
fn map_double(xs : List(Int)) : List(Int) do
  match xs with
  | Nil -> Nil()
  | Cons(head, tail) -> Cons(head * 2, map_double(tail))
  end
end
```

In the `Cons` arm, after Perceus RC insertion:
- `xs` is last-used at the case scrutinee → `EDecRC xs` inserted
- Immediately after, `alloc Cons(...)` allocates a same-shape constructor

FBIP detection finds:
```
EDecRC (AVar xs);
ELet (result, EAlloc (TCon("Cons", [...]), [h2, rest]), ...)
```

`xs.v_ty = TCon("Cons", [TInt; TCon("List",[TInt])])` and the new alloc is also
`TCon("Cons", ...)` — same shape. Replace with:

```
ELet (result, EReuse (AVar xs, TCon("Cons", [...]), [h2, rest]), ...)
```

At runtime: instead of freeing `xs`'s memory and then allocating fresh memory for
the new `Cons` cell, the runtime writes the new `Cons` fields directly over `xs`.
Cache-hot, allocator-free.

### Example 4 — Linear value gets EFree, not EDecRC

```march
fn use_ptr(p : linear Ptr(Int)) : Int do
  let n = *p
  free(p)   -- explicit free in source; after linearity lowering: EFree
  n
end
```

After Perceus: `p.v_lin = Lin`, so at the last use an `EFree` is inserted (no RC
increment was ever needed for `p` — the type system enforced single ownership).

---

## The Calling Convention

The analysis depends on a consistent caller/callee ownership convention:

**Caller's responsibilities:**
- For each argument `AVar v`:
  - If `v` is last-used at this call: pass as-is (ownership transfer).
  - If `v` is used again after the call: insert `EIncRC (AVar v)` before the call.
- The callee owns all parameters on entry.

**Callee's responsibilities:**
- Parameters are owned on entry (rc contribution = 1).
- Unused parameters must be released (Rule 4 — dead binding).
- Returned value is owned by the callee; ownership transfers to caller.

This convention is statically enforced by the Perceus pass — no runtime tagging.

---

## Implementation Structure

```
lib/tir/perceus.ml
```

```ocaml
(* Phase 1: liveness *)
type live_set = StringSet.t

val live_before : Tir.expr -> live_set -> live_set
(* Returns variables live before evaluating expr, given live_after *)

(* Phase 2: RC insertion *)
val insert_rc : Tir.fn_def -> Tir.fn_def
(* Inserts EIncRC, EDecRC, EFree into a single fn_def *)

(* Phase 3: elision *)
val elide_cancel_pairs : Tir.fn_def -> Tir.fn_def
(* Removes adjacent EIncRC/EDecRC pairs for same variable *)

(* Phase 4: FBIP *)
val insert_fbip : Tir.fn_def -> Tir.fn_def
(* Replaces EDecRC + EAlloc same-shape with EReuse *)

(* Entry point *)
val perceus : Tir.tir_module -> Tir.tir_module
(* Runs all four phases over every fn_def in tm_fns *)
```

### dune

Add `perceus` to the `march_tir` library modules:
```
(modules tir pp lower mono defun perceus)
```

### bin/main.ml

After defunctionalization:
```ocaml
let tir = March_tir.Defun.defunctionalize tir in
let tir = March_tir.Perceus.perceus tir in
```

---

## Interaction with Other Passes

### Pre-Perceus (defun output)
- No `EIncRC`, `EDecRC`, `EFree`, `EReuse` nodes in the TIR.
- All heap allocations are `EAlloc`.
- Closures are `EAlloc (TCon("$Clo_...", []), ...)`.

### Post-Perceus (perceus output)
- `EAlloc` nodes remain (stack promotion is Pass 5).
- RC nodes appear around non-last uses and dead bindings.
- `EReuse` replaces `EDecRC + EAlloc` at FBIP sites.
- Linear/affine last uses have `EFree` appended.

### Pass 5 (Escape Analysis)
Escape analysis runs after Perceus. It promotes stack-eligible `EAlloc`s to
`ELet` stack bindings. An `EAlloc` that is immediately followed by `EDecRC` or
`EFree` (because the result is unused) is also a candidate for elimination.

---

## Scope Limitations and Simplifications (v1)

1. **No interprocedural RC elision.** If a caller passes a last-use argument and
   the callee immediately drops it, the dec in the callee and the "no-inc" in the
   caller are correct — but the caller might also have inserted an inc for the same
   variable earlier in the function. A whole-program analysis could eliminate
   more, but per-function is correct and cheap.

2. **FBIP shape check is structural, not size-based.** Two constructors of the
   same name are considered same-shape if they have the same field count. In v1 we
   require identical constructor name AND field count. Post-monomorphization, all
   fields are pointer-sized or primitive, so this is conservative and safe.

3. **`ELetRec` bodies (non-lambda)** — genuine mutually-recursive `fn_def` groups
   within a function body are rare post-defun. Perceus treats them like nested
   functions: liveness is computed for each `fn_def` independently, with a
   conservative approximation that all free variables of the inner function are
   live at the `ELetRec` site.

4. **No `EReuse` for closures.** `$Clo_...` structs can in principle be reused
   the same way, but their field count and types depend on capture set, making
   shape matching more complex. Deferred to a later optimization.

---

## Open Questions

1. **FBIP: size-based vs. name-based shape matching.** If two constructors have
   the same total memory footprint (same number of pointer fields), can their
   memory be reused across constructor kinds? This requires a size oracle and
   changes the tag field but not the allocation size. Deferring to the LLVM
   emit pass where sizes are concrete.

2. **RC for closures / `$Clo_` structs.** After defun, closures are heap-allocated
   `TCon("$Clo_...", [])` values with `Unr` linearity. Perceus handles them
   uniformly — they get `EDecRC` at last use like any other heap value. Is this
   correct? Yes: closures are ref-counted; when the last reference to a closure is
   dropped, the closure struct is freed. The captured free variables inside have
   already had their RC adjusted when the closure was created.

3. **RC on `TString` values.** Strings are heap-allocated structs with their own
   RC field. After monomorphization, `TString` uses appear as `EApp` to string
   builtins. The Perceus pass should treat string-typed variables as `Unr`
   (ref-counted) unless the source annotates them `affine`. Strings are never
   linear because literals are shared.

4. **Interaction with actor message send.** `ESend (cap, msg)` transfers ownership
   of `msg` to the target actor. From Perceus's perspective, this is a last use
   of `msg` (ownership transfer, no inc needed). The `cap` may or may not be
   linear depending on the capability type — if linear, `EFree cap` follows;
   if unrestricted (shared pid), no RC change.

5. **RC counter width and atomicity.** For values within a single actor, RC
   operations are non-atomic (actors are single-threaded). For values shared
   across threads (none in v1 due to actor isolation), atomic operations would
   be needed. Decision: non-atomic RC for v1; revisit if shared-memory primitives
   are added.
