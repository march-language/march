# Capability System Design — Phase 3

**Date:** 2026-06-18
**Status:** Draft
**Depends on:** Phase 2 (proof caps, `Handle(R, S)`, `Tagged(X, T)`, env records — all implemented)

---

## Overview

Phase 2 introduced four new capability mechanisms and left three items explicitly deferred:

> **Q2 — Typestate pattern match refinement:** Deferred. GADT-style refinement is a future type system extension.
> **Q6 — Explicit bounded type-parameter syntax:** Deferred to Phase 3.
> **Phase 2e — Full panic-as-capability:** Deferred to its own sub-spec.

It also split Phase 2c's `Tagged(X, T)` work: the type-system parts (narrowing rules, `cap_subsumes` additions) shipped; the IR-level enforcement (conditional lowering/DCE pass for policy tags) did not.

Phase 3 completes what Phase 2 started:

1. **Explicit bounded type parameters** — `fn f[S : ConnState](...)` syntax that makes `Handle` and `Tagged` APIs self-documenting and checkable without implicit inference
2. **Policy-tag DCE pass** — the missing half of Phase 2c: IR-level enforcement that `NoAlloc`/`Realtime` functions contain no allocation or abort sites
3. **No-panic modules** — an opt-in module directive (`opts no_panic`) that statically verifies a module contains no expressions that can panic; first step toward the full `Cap(Panic)` hierarchy
4. **Full `Cap(Panic)` hierarchy** — granular `Cap(Panic.Arithmetic)` / `Cap(Panic.Bounds)` etc. with implicit threading (high cost; deferred sub-spec)
5. **GADT state refinement** — `Handle` state narrowing inside match arms (exploratory; complex)

All of Phase 3 is purely additive. No runtime changes.

---

## 1. Explicit Bounded Type Parameters

### Motivation

Phase 2's `Handle(R, S)` and `Tagged(X, T)` rely on implicit type variable inference for state and policy parameters. This works — but library authors cannot express constraints directly in function signatures:

```march
-- Today: S is implicit. What states can S be? Unknown without reading the transitions block.
fn with_conn(h : Handle(Conn, S), f : (Handle(Conn, Open)) -> (a, Handle(Conn, Open))) : (a, Handle(Conn, S))
```

A reader cannot tell what `S` may be. Nothing stops a caller from instantiating `S = Int` — the type checker only catches it if an incompatible operation actually fires, not at the boundary where the intent was stated. For combinator functions that thread handles through without inspecting state, the failure can be silent until deep inside the body.

Phase 3a adds explicit syntax:

```march
fn with_conn[S : ConnState](h : Handle(Conn, S), f : (Handle(Conn, Open)) -> (a, Handle(Conn, Open))) : (a, Handle(Conn, S))
```

`S : ConnState` tells the reader (and compiler) that `S` must be one of the variants of `ConnState`, caught at the call site rather than wherever the mismatch eventually surfaces.

The combinator pattern is the primary motivation. Simple concrete-state functions like `fn open_conn(h : Handle(Conn, Closed)) : Handle(Conn, Open)` do not need bounds — their state parameters are already concrete. Bounds matter when writing *generic over state*:

```march
-- Generic combinator: transitions from S to T, runs f, transitions back
fn bracket[S : ConnState, T : ConnState](
  h    : Handle(Conn, S),
  pre  : (Handle(Conn, S)) -> Handle(Conn, T),
  f    : (Handle(Conn, T)) -> (a, Handle(Conn, T)),
  post : (Handle(Conn, T)) -> Handle(Conn, S)
) : (a, Handle(Conn, S))

-- Read-only inspection: works in any state, returns state name
fn state_label[S : ConnState](h : Handle(Conn, S)) : String

-- Policy-generic processing
fn process[P : AllocPolicy](cap : Tagged(Alloc, P), buf : Buffer(Byte)) : Buffer(Byte)
```

Without explicit bounds, `bracket`'s four type variables are anonymous. With them, a reader knows exactly what domain `S` and `T` inhabit before reading the body.

---

### Syntax

Type parameter bounds use `[TypeVar : BoundType, ...]` after the function name, before the value-parameter list:

```march
fn open[S : ConnState](h : Handle(Conn, S)) : Handle(Conn, Open)
fn close[S : ConnState](h : Handle(Conn, S)) : Handle(Conn, Closed)

fn process[P : AllocPolicy](cap : Tagged(Alloc, P), buf : Buffer(Byte)) : Buffer(Byte)
fn fft[N : TNat](cap : Tagged(SIMD, N), buf : Buffer(Float32, N)) : Buffer(Complex32, N)
```

Multiple bounds, comma-separated:

```march
fn bridge[S : ConnState, P : AllocPolicy](h : Handle(Conn, S), cap : Tagged(Alloc, P)) : ()
```

The same type variable may appear in only one bound. Bounds appear only on named `fn` and `pfn` declarations — lambdas continue to use implicit inference.

A function without bounds is unchanged from today. Bounds are purely additive.

---

### Valid bound kinds

Three kinds of bound are legal. The bound type must be one of these; any other type is rejected at the declaration site.

**1. ADT bound** — `BoundType` is a sum type. `[S : ConnState]` means `S` must instantiate to one of `ConnState`'s constructors (`Closed`, `Open`, `Errored`). This is the main use case for Handle state parameters.

```march
type ConnState = Closed | Open | Errored

fn transition[S : ConnState](h : Handle(Conn, S), ...) : Handle(Conn, Open)
```

The check at instantiation: given `S = X`, verify that `X` is a constructor of `ConnState` (i.e., `X ∈ { Closed, Open, Errored }`). If `X` is itself a type variable (polymorphic caller), the bound propagates — see §Propagation below.

**2. Interface bound** — `BoundType` is an `interface` name. `[a : Ord]` means `a` must have an `impl Ord(a)` in scope. This is the existing typeclass-constraint mechanism; the bracket syntax unifies both cases.

```march
fn sort[a : Ord](xs : List(a)) : List(a)
```

Internally, interface bounds and ADT bounds are stored differently in `env.tv_bounds` (see §Implementation), but the surface syntax is identical.

**3. TNat bound** — `BoundType` is `TNat`. `[N : TNat]` means `N` must be a type-level natural number literal or expression. `TNat` is a kind, not a regular ADT; the bound check verifies that the instantiated type is a `TNat` node rather than an arbitrary type.

```march
fn fft[N : TNat](cap : Tagged(SIMD, N), buf : Buffer(Float32, N)) : Buffer(Complex32, N)
fn zeros[M : TNat, N : TNat]() : Matrix(M, N, Float)
```

**Rejected at declaration time:** if `BoundType` is a concrete non-ADT type (`Int`, `String`, `Bool`, a record type, a function type), it is rejected with:

```
Error: bound type `Int` is not a valid type-variable bound.
Bounds must be a sum type (ADT), an interface, or `TNat`.
```

---

### Semantics: checked during typechecking at call sites

Bounds are discharged during **type-checking** at each call site — not during bidirectional inference, and not in the TIR monomorphization pass. The existing `pending_constraints` mechanism (`lib/typecheck/typecheck.ml`) already works this way for `CNum` and `CInterface` constraints; ADT and TNat bounds follow the same pattern.

1. **Inference runs first, unconstrained by bounds.** The type variable `S` is unified normally against the call site's argument types. Bounds do not participate in unification and do not drive inference.

2. **Bounds are emitted as constraints.** When a call site instantiates a function with bounds, the type-checker emits bound constraints (e.g., `CADTBound("ConnState", T)`) into `pending_constraints` alongside any existing `CInterface` constraints.

3. **Constraints are discharged after each call site.** When `S` resolves to a concrete type `T`, the bound constraint fires: check that `T` satisfies the bound. If it does not, report an error at the call site.

This means bounds cannot rescue inference — they cannot help the compiler choose between two types that would both unify. They are purely a gate on the resolved result.

**Consequence for error locality:** The error appears at the call site where the type variable was instantiated to an illegal value, not inside the function body where the mismatch would otherwise surface. This is the primary benefit.

---

### Propagation to polymorphic callers

If a caller `g` calls `f[S : ConnState]` but leaves `S` unresolved (because `g` is itself generic over `S`), `g` must also declare `[S : ConnState]` — or the compiler reports an error at `g`'s definition:

```march
-- OK: g propagates the bound
fn g[S : ConnState](h : Handle(Conn, S)) : String do
  state_label(h)   -- state_label[S : ConnState] — S is still bound
end

-- ERROR: g uses state_label but doesn't constrain S
fn bad_g(h : Handle(Conn, S)) : String do
  state_label(h)   -- S is free, no bound declared
end
```

```
Error: `state_label` requires `S : ConnState` but `S` is unconstrained here.
Add `[S : ConnState]` to `bad_g`'s type parameter list:

  fn bad_g[S : ConnState](h : Handle(Conn, S)) : String do
```

Because March monomorphizes fully, propagation terminates: every chain of generic-over-state calls must eventually reach a concrete instantiation site.

---

### Error messages

**Wrong type at call site:**

```
Error: type variable `S` was instantiated to `Int` but must be a
       constructor of `ConnState`.

  transition(my_int_value, ...)
  ^^^^^^^^^^
  
  `Int` is not a variant of `ConnState`. Valid variants:
    Closed | Open | Errored
```

**Missing bound propagation:**

```
Error: `state_label` requires `S : ConnState` but `S` is unconstrained in `g`.

  fn g(h : Handle(Conn, S)) : String do
    state_label(h)   ← S used here without bound
    
  Add `[S : ConnState]` to `g`:
  
    fn g[S : ConnState](h : Handle(Conn, S)) : String do
```

**Invalid bound type at declaration:**

```
Error: `String` is not a valid type-variable bound.
Bounds must be a sum type (ADT), an interface, or `TNat`.

  fn bad[S : String](...)
         ^^^^^^^^^^
```

---

### What bounds are NOT

- **Not variance annotations.** `[S : ConnState]` says nothing about covariance or contravariance of `S` in the type. March does not have variance annotations.
- **Not coercion.** The bound does not cause implicit conversion. If `S = Closed` and `Open` is needed, that is still a type error — the bound only gates the *domain* of `S`.
- **Not a recursive/self-referential constraint.** `[S : Container(S)]`-style F-bounded polymorphism is not supported in Phase 3. Deferred.
- **Not an exhaustiveness constraint.** The compiler does not require the function body to handle all constructors of the bound type. The body must only typecheck against the declared signature.

---

### Parser conflict analysis

The `[bound_list]` appears after the function name and before `(`. The current `fn_decl` production in `lib/parser/parser.mly` is:

```
fn_decl:
  | FN; name = lower_name; LPAREN; params = ...; RPAREN;
    ret = option(ret_annot); guard = option(when_guard); DO; body = block_body; END
```

After `lower_name`, the only valid next token today is `LPAREN`. `LBRACKET` does not appear in any declaration-position rule — there is no other grammar production that puts `[` after a function name. Adding a second alternative is unambiguous:

```
fn_decl:
  | FN lower_name LPAREN params RPAREN ...                             (* no bounds *)
  | FN lower_name LBRACKET bounds RBRACKET LPAREN params RPAREN ...    (* Phase 3a *)
```

`LBRACKET` after a lower name in declaration position can only be bounds syntax — lists and arrays only appear inside expression contexts. No new LALR(1) conflicts are introduced.

Note: `pfn` shares the same production structure. Both `FN` and `PFN` tokens would need the bounds alternative, or `fn_decl` can be refactored to a shared `fn_head` nonterminal that covers both visibility tokens.

---

### Implementation notes

**AST.** Add `fn_bounds : (string * Ast.ty) list` to the `fn_def` record in `lib/ast/ast.ml`. (There is no separate `DPFn` — both `fn` and `pfn` produce `DFn`; privacy is `fn_vis = Private`. The `fn_def` record is shared.)

```ocaml
and fn_def = {
  fn_name    : name;
  fn_vis     : visibility;
  fn_doc     : string option;
  fn_attrs   : string list;
  fn_ret_ty  : ty option;
  fn_clauses : fn_clause list;
  fn_bounds  : (string * ty) list;   (* NEW: [(type_var_name, bound_type)] *)
}
```

**`constraint_` extension.** The existing `pending_constraints : constraint_ list ref` field in `env` accumulates type constraints that are discharged after unification. Extend `constraint_` in `typecheck.ml` to cover the two new bound kinds:

```ocaml
type constraint_ =
  | CNum       of ty
  | COrd       of ty
  | CInterface of string * ty
  | CADTBound  of string * ty   (* NEW: ty must be a constructor of ADT named string *)
  | CTNatBound of ty            (* NEW: ty must be a TNat node *)
```

`CInterface` already handles interface bounds (`[a : Ord]`) — no new constraint_ variant needed for those.

**At function definition** (`infer_fn_def`). Parse `fn_bounds` from the AST node. Validate that each bound type is legal (ADT, interface, or `TNat`; anything else is an immediate error). Store the validated bounds in a local map `bound_vars : (string * constraint_kind) StrMap.t` scoped to this function.

**At call sites** (`instantiate_fn_scheme` or the unification path). When instantiating a polymorphic function that has bounds, emit the appropriate constraint for each bound type variable:
- Bound is an ADT name → emit `CADTBound(adt_name, T)` where `T` is the inferred type for that variable
- Bound is an interface name → emit `CInterface(iface_name, T)` (existing mechanism, no new code)
- Bound is `TNat` → emit `CTNatBound(T)`

**Constraint discharge.** When `pending_constraints` are checked:
- `CADTBound(name, T)`: call `lookup_ctor_in_type (ctor_name_of T) name env`. `lookup_ctor_in_type` already exists (`lib/typecheck/typecheck.ml:489`) and takes `constructor_name -> adt_name -> env -> ctor_info option`. If it returns `None`, the type is not a constructor of that ADT — emit the error. If `T` is still a type variable, propagate the constraint to it.
- `CTNatBound(T)`: match `T` against the internal `ty` type — valid iff `T = TNat _` (a literal) or `T = TNatOp _` (a type-level arithmetic expression). Otherwise error.

**Eval, TIR, codegen, runtime:** no changes. Bounds are fully erased after typechecking — they produce no nodes in TIR or LLVM IR.

**Estimated scope:** ~350 lines (`parser.mly` ~50, `ast.ml` ~15, `typecheck.ml` ~285). No eval, TIR, codegen, or runtime changes. ~10 new capability tests.

---

## 2. Policy-Tag DCE Pass

### Motivation

Phase 2c (`Tagged(X, T)`) ships the type-system enforcement — a function taking `Tagged(DSP, Realtime)` is rejected at compile time if it also takes `Cap(Alloc)` or `Cap(IO)`. But this is declaration-level checking. The actual compiled code for a `Realtime`-tagged function might still contain allocation instructions introduced by inlining or by code that the type system allowed to enter via other paths.

The goal: **when a function is specialized to a policy that excludes allocation (or panic, or IO), the compiled TIR for that specialization must contain no sites that violate the policy.**

### Two enforcement modes

**Type-level (Phase 2c, shipped):** The function signature is checked. A `Realtime`-tagged function cannot accept a `Cap(Alloc)` parameter. The type system prevents the *interface* from lying.

**IR-level (Phase 3b, this section):** After monomorphization, a new audit pass walks the TIR body of every function whose parameter list includes a `Tagged(_, P)` where P names a constraining policy, and reports any policy-violating operations. Audit-only first; DCE (conditional branch pruning) is a follow-up.

---

### TIR representation of `Tagged` constraints (verified)

After `Mono.monomorphize`, all type variables are replaced with concrete types.
A parameter `cap : Tagged(DSP, Realtime)` becomes a `var` with:

```ocaml
{ v_name = "cap";
  v_ty   = TCon("Tagged", [TCon("DSP", []); TCon("Realtime", [])]);
  v_lin  = Unr }
```

`Tagged` survives monomorphization because it is a regular `TCon` (arity 2, registered at typecheck line 1587 as `("Tagged", 2)`). The pass can identify constrained functions by scanning `fn_params` for params whose `v_ty` matches `TCon("Tagged", [_; TCon(policy_name, [])])`. This is the correct detection strategy.

---

### Pipeline position (verified)

The compilation pipeline in `bin/main.ml` (lines 1064–1105) is:

```
Lower → Mono → Fusion → [Phase 3b HERE] → Defun → Known_call → Perceus → Escape → Opt → Emit
```

The pass inserts between `Fusion.run` (line 1089) and `Defun.defunctionalize` (line 1092). It must run after mono (needs concrete types to identify policies) and before defun (closures are still first-class, making body walking cleaner). `Fusion` can be run before the audit because it never introduces allocations or IO calls.

Integration in `bin/main.ml`:
```ocaml
let tir = March_tir.Fusion.run ~changed:(ref false) tir in
(* NEW: policy audit *)
let () = March_tir.Policy_dce.audit ~io_fns:io_fn_set tir in
let tir = March_tir.Defun.defunctionalize tir in
```

The same insertion point applies in `lib/jit/repl_jit.ml` (which has its own pipeline invocation).

---

### Policy table

```ocaml
(* lib/tir/policy_dce.ml *)

type policy_constraint =
  | NoAlloc   (* prohibits EAlloc and EStackAlloc nodes *)
  | NoPanic   (* prohibits transitive calls to panic-surface builtins *)
  | NoIO      (* prohibits calls to IO-needful functions *)

let policy_table : (string * policy_constraint list) list = [
  ("NoAlloc",  [NoAlloc]);
  ("NoPanic",  [NoPanic]);
  ("Realtime", [NoAlloc; NoPanic; NoIO]);  (* all three *)
]
```

`Realtime` carries all three because a realtime callback that prints to stdout or blocks on a file read is as broken as one that allocates.

---

### Phase A: transitive panic analysis (reusing `Purity.ml` architecture)

`Purity.ml` already contains `impure_fns_of_module` — a fixpoint that computes which module functions are transitively impure. The panic analysis uses the same algorithm with a narrower seed set.

**Panic-surface builtins** (verified against `typecheck.ml` lines 1243–1246 and `purity.ml` lines 38–47):

```ocaml
let direct_panic_builtins = Purity.StringSet.of_list [
  (* Integer arithmetic — panic on zero divisor *)
  "int_div"; "int_mod"; "int_div_euclid"; "int_mod_euclid";
  "/"; "%";
  (* Explicit abort *)
  "panic"; "panic_"; "todo_"; "unreachable_";
]
```

Note: `"assert"` is desugared to `if not cond do panic_ "..." end` before lowering, so it does not appear as a direct `EApp` in TIR — it is already handled by the `panic_` entry.

`unwrap`, `expect`, `List.nth`, `List.hd`, etc. are *stdlib* functions, not builtins. Their TIR bodies contain `EApp({v_name="panic_"}, ...)`. The fixpoint picks them up automatically — after seed expansion, `unwrap$Option$Int`, `List.nth$Int`, and friends all join the `panicky` set because their bodies call `panic_`.

**Algorithm** (adapted from `Purity.impure_fns_of_module`):

```ocaml
let panicky_fns_of_module (m : Tir.tir_module) : Purity.StringSet.t =
  let seed = direct_panic_builtins in
  (* body_calls: set of function names directly called in an expression *)
  let rec calls_in_expr acc = function
    | Tir.EApp (f, _) -> Purity.StringSet.add f.Tir.v_name acc
    | Tir.ELet (_, rhs, body) -> calls_in_expr (calls_in_expr acc rhs) body
    | Tir.ECase (_, branches, def) ->
        let acc = List.fold_left (fun a b -> calls_in_expr a b.Tir.br_body) acc branches in
        Option.fold ~none:acc ~some:(calls_in_expr acc) def
    | Tir.ELetRec (fns, body) ->
        List.fold_left (fun a fd -> calls_in_expr a fd.Tir.fn_body)
          (calls_in_expr acc body) fns
    | Tir.ESeq (a, b) -> calls_in_expr (calls_in_expr acc a) b
    | _ -> acc
  in
  let rec fixpoint panicky =
    let panicky' = List.fold_left (fun acc fd ->
      if Purity.StringSet.mem fd.Tir.fn_name acc then acc
      else
        let callees = calls_in_expr Purity.StringSet.empty fd.Tir.fn_body in
        if not (Purity.StringSet.is_empty
                  (Purity.StringSet.inter callees panicky))
        then Purity.StringSet.add fd.Tir.fn_name acc
        else acc
    ) panicky m.Tir.tm_fns in
    if Purity.StringSet.cardinal panicky' = Purity.StringSet.cardinal panicky
    then panicky'
    else fixpoint panicky'
  in
  fixpoint seed
```

The fixpoint terminates because `tm_fns` is finite and the set only grows.

---

### Phase B: NoAlloc check

Walk an `expr` tree. An allocation violation is any `EAlloc` or `EStackAlloc` node.

```ocaml
(* Returns the first violating node found, None if clean *)
let rec find_alloc : Tir.expr -> Tir.expr option = function
  | Tir.EAlloc _ as e      -> Some e
  | Tir.EStackAlloc _ as e -> Some e
  | Tir.ELet (_, rhs, body) ->
      (match find_alloc rhs with Some _ as r -> r | None -> find_alloc body)
  | Tir.ECase (_, branches, def) ->
      let r = List.find_map (fun b -> find_alloc b.Tir.br_body) branches in
      (match r with Some _ -> r | None -> Option.bind def find_alloc)
  | Tir.ELetRec (fns, body) ->
      let r = List.find_map (fun fd -> find_alloc fd.Tir.fn_body) fns in
      (match r with Some _ -> r | None -> find_alloc body)
  | Tir.ESeq (a, b) ->
      (match find_alloc a with Some _ as r -> r | None -> find_alloc b)
  | _ -> None
```

`EAlloc` is heap allocation; `EStackAlloc` is inserted by `Escape` analysis — but since the audit runs *before* `Escape`, `EStackAlloc` cannot appear yet at this pipeline position. The check is future-proof: if the pipeline order ever changes, both cases are handled.

---

### Phase C: NoPanic check

Walk an `expr` tree checking `EApp` call targets against the `panicky` set from Phase A.

```ocaml
let rec find_panic (panicky : Purity.StringSet.t) : Tir.expr -> string option =
  function
  | Tir.EApp (f, _) when Purity.StringSet.mem f.Tir.v_name panicky ->
      Some f.Tir.v_name
  | Tir.ELet (_, rhs, body) ->
      (match find_panic panicky rhs with
       | Some _ as r -> r
       | None -> find_panic panicky body)
  (* ... same structural recursion as find_alloc *)
  | _ -> None
```

---

### Phase D: NoIO check and the `tm_io_fns` field

This is the gap identified in the original spec. The fix is a one-field addition to `tir_module` and a small extraction step in `bin/main.ml`.

**Root cause.** `env.module_caps : (string * string list) list` tracks `(module_name → cap_paths)` accumulated during `check_module`. The cap paths include `"IO"`, `"IO.FileSystem"`, etc. This information exists at typecheck time but is not threaded into TIR.

**Fix: add `tm_io_fns` to `tir_module`.**

```ocaml
(* lib/tir/tir.ml — add one field *)
type tir_module = {
  tm_name    : string;
  tm_fns     : fn_def list;
  tm_types   : type_def list;
  tm_externs : extern_decl list;
  tm_exports : string list;
  tm_tests   : (string * string) list;
  tm_io_fns  : string list;
  (** Names of functions that require Cap(IO), extracted from typecheck env
      at lower time. Used by policy_dce's NoIO check. Empty in pre-policy builds. *)
}
```

**Extraction at `bin/main.ml`.**

`check_module_full` (typecheck line 7006) returns the final `env`. From it, extract all function names that appeared under an `"IO"`-capped module:

```ocaml
(* bin/main.ml — after check_module_full returns *)
let io_fn_set =
  List.concat_map (fun (mod_name, caps) ->
    if List.exists (fun c -> c = "IO" || String.length c > 3
                             && String.sub c 0 3 = "IO.") caps
    then (* collect function names from that module in the tir *)
         (* simplest: record the module_name prefix and match fn names at audit time *)
         [mod_name]
    else []
  ) final_env.module_caps
```

Wait — `module_caps` maps module *names* to cap lists, not function names. The function names are inside those modules. The most practical strategy: store the *module names that need IO* in `tm_io_fns`, then in the audit pass match `EApp({v_name=f}, _)` against functions whose prefix is in `io_mod_set` — i.e., `f` starts with `"ModName."`.

```ocaml
(* In policy_dce.ml — NoIO check *)
let io_mod_set = Purity.StringSet.of_list m.Tir.tm_io_fns in
let fn_needs_io f_name =
  (* f_name after mono looks like "Http.get$String" or "HttpClient.run" *)
  Purity.StringSet.exists (fun mod_name ->
    let prefix = mod_name ^ "." in
    String.length f_name >= String.length prefix
    && String.sub f_name 0 (String.length prefix) = prefix
  ) io_mod_set
```

And then apply `impure_fns_of_module`-style fixpoint seeded with `fn_needs_io` to find transitive IO callers.

**Populating `tm_io_fns`.**

In `bin/main.ml`, after `check_module_full` and before `Lower.lower_module`:

```ocaml
let io_modules =
  List.filter_map (fun (mod_name, caps) ->
    if List.exists (String.equal "IO") caps
    || List.exists (fun c -> String.length c > 3 && String.sub c 0 3 = "IO.") caps
    then Some mod_name
    else None
  ) final_env.module_caps
in
(* Pass io_modules to Lower, which stores them in tm_io_fns *)
```

`Lower.lower_module` gets a new optional `~io_modules` parameter that is stored verbatim into the produced `tir_module.tm_io_fns`.

Alternatively (simpler): `tm_io_fns` is filled post-lowering in `bin/main.ml` by direct field update:
```ocaml
let tir = { tir with March_tir.Tir.tm_io_fns = io_modules } in
```
This avoids touching `lower.ml`'s signature.

---

### Error reporting (no span problem)

TIR does not carry source spans — they are dropped during `lower.ml`. Violations therefore cannot point to a precise source line. The error message names the **function** and the **violation type**, which is actionable even without a line number.

**Strategy:** `policy_dce.audit` returns a `(string * string) list` of `(violating_function_name, message)` pairs. The caller (`bin/main.ml`) adds them to the existing `Err.ctx` using `Err.error ~span:Ast.dummy_span`:

```ocaml
(* bin/main.ml, after the audit call *)
List.iter (fun (fn_name, msg) ->
  Err.error errors ~span:Ast.dummy_span msg
) (March_tir.Policy_dce.audit ~io_fns:io_module_set tir)
```

`Ast.dummy_span` renders as no location in the error output — the user sees a bare "Error: ..." with no file/line. That is correct and honest: the violation is detected at the IR level after source info is gone.

**Message format:**

```
Error: function `dsp_callback` (specialized to `Tagged(DSP, Realtime)`)
       allocates heap memory (EAlloc).
       Realtime functions must not allocate.
       Move the allocation outside the realtime boundary.
```

```
Error: function `timer_tick` (specialized to `Tagged(Ticker, NoPanic)`)
       calls `List.nth`, which can panic on out-of-bounds access.
       Use `List.nth_opt` to return `None` instead.
```

```
Error: function `render_callback` (specialized to `Tagged(UI, Realtime)`)
       calls `Http.get`, which requires `Cap(IO)`.
       IO is forbidden in Realtime functions.
```

---

### Full `audit` function signature

```ocaml
(* lib/tir/policy_dce.ml *)

val audit : tir_module -> (string * string) list
(** [audit m] walks every function in [m] whose parameter list includes
    a [Tagged(_, P)] parameter where [P] is a constrained policy.
    Returns a list of [(fn_name, error_message)] violation reports.
    Returns [[]] if no violations are found. *)
```

The `tm_io_fns` field on `tir_module` is the NoIO oracle; no extra parameter needed.

---

### Structural walk utility

To avoid duplicating the recursive walk across the three check functions, extract a single `fold_expr` that accumulates violations:

```ocaml
let rec fold_expr (f : 'a list -> Tir.expr -> 'a list) acc expr =
  let acc = f acc expr in
  match expr with
  | Tir.ELet (_, rhs, body) -> fold_expr f (fold_expr f acc rhs) body
  | Tir.ECase (_, branches, def) ->
      let acc = List.fold_left (fun a b -> fold_expr f a b.Tir.br_body) acc branches in
      Option.fold ~none:acc ~some:(fold_expr f acc) def
  | Tir.ELetRec (fns, body) ->
      let acc = List.fold_left (fun a fd -> fold_expr f a fd.Tir.fn_body) acc fns in
      fold_expr f acc body
  | Tir.ESeq (a, b) -> fold_expr f (fold_expr f acc a) b
  | _ -> acc
```

Each check becomes a one-liner pattern match passed as `f`.

---

### Complete module outline

```
lib/tir/policy_dce.ml  (~250 lines)
  module StringSet = Set.Make(String)

  -- Policy table
  type policy_constraint = NoAlloc | NoPanic | NoIO
  val policy_table : (string * policy_constraint list) list

  -- Panic analysis
  val direct_panic_builtins : StringSet.t
  val panicky_fns_of_module : Tir.tir_module -> StringSet.t

  -- IO analysis (uses tm_io_fns)
  val io_fns_of_module : Tir.tir_module -> StringSet.t

  -- Body walkers
  val fold_expr : ('a list -> Tir.expr -> 'a list) -> 'a list -> Tir.expr -> 'a list
  val check_noalloc : Tir.fn_def -> string option
  val check_nopanic : StringSet.t -> Tir.fn_def -> string option
  val check_noio    : StringSet.t -> Tir.fn_def -> string option

  -- Entry point
  val audit : Tir.tir_module -> (string * string) list
```

Changes to existing files:

| File | Change | ~Lines |
|------|--------|--------|
| `lib/tir/tir.ml` | Add `tm_io_fns : string list` to `tir_module` | +2 |
| `lib/tir/tir.ml` | Update all `tir_module` constructors to include `tm_io_fns = []` | +N (grep `tm_tests`) |
| `lib/tir/dune` | Add `policy_dce` to library modules list | +1 |
| `bin/main.ml` | Extract `io_modules` from final typecheck env, patch `tir.tm_io_fns`, call `Policy_dce.audit` | +15 |
| `lib/jit/repl_jit.ml` | Same audit call in JIT pipeline | +10 |

---

### Integration with Phase 2c narrowing rules

Phase 2c's `check_decl` Check 7 (typecheck line ~4813) pattern-matches on `Tagged(_, Realtime)` *at the type-checker level* and rejects co-presence of `Cap(Alloc)` or `Cap(IO)` in the same signature. The Phase 3b audit is **complementary**, not redundant:

- Phase 2c catches: "your signature accepts `Cap(Alloc)` alongside `Tagged(_, Realtime)`"
- Phase 3b catches: "your body allocates, even though you didn't accept `Cap(Alloc)`" (e.g., allocation slipped in via a helper that was typed generically)

Both checks are necessary. Phase 2c gates at the declaration boundary; Phase 3b gates at the IR body.

---

### Deferred: DCE mode (conditional branch elimination)

Audit mode reports violations as errors and lets the programmer fix them manually. DCE mode would *automatically eliminate* branches that are only reachable under a policy that is statically absent.

Example:
```march
fn process[P : AllocPolicy](cap : Tagged(Alloc, P), buf : Buffer(Byte)) : Buffer(Byte) do
  if can_alloc(cap) do
    let result = Buffer.copy(buf)   -- allocates
    transform(result)
  else
    transform_in_place(buf)         -- no allocation
  end
end
```

When specialized to `Tagged(Alloc, NoAlloc)`, the `can_alloc` branch is statically dead. DCE mode would eliminate it, making the `NoAlloc` specialization clean without programmer intervention.

This requires:
1. A policy-value type in TIR (currently `Tagged`'s second arg is just a `TCon` with no special semantics)
2. Conditional expression forms that DCE can act on (`if can_alloc(cap)` must desugar to something the pass can pattern-match)

Both are significant. DCE mode is a follow-up; file separately when a use case requires it.

---

### Test cases (~8 new tests in `tag_and_typestate` or new `policy_dce` suite)

| # | Description | Expected |
|---|-------------|---------|
| 1 | `Tagged(DSP, NoAlloc)` fn with `List.map` (allocates) | error |
| 2 | `Tagged(DSP, NoAlloc)` fn with no allocation | no error |
| 3 | `Tagged(T, NoPanic)` fn calls `List.nth` | error |
| 4 | `Tagged(T, NoPanic)` fn uses `List.nth_opt` | no error |
| 5 | `Tagged(T, NoPanic)` fn calls a helper that calls `panic_` | error (transitive) |
| 6 | `Tagged(T, Realtime)` fn calls IO function | error |
| 7 | `Tagged(T, Realtime)` fn that is clean | no error |
| 8 | Non-tagged fn with allocation | no error (not checked) |

---

### Estimated scope

| File | Lines |
|------|-------|
| `lib/tir/policy_dce.ml` (new) | ~250 |
| `lib/tir/tir.ml` | +5 |
| `lib/tir/dune` | +1 |
| `bin/main.ml` | +20 |
| `lib/jit/repl_jit.ml` | +10 |
| `test/test_compiler.ml` | +100 |
| **Total** | **~390** |

No runtime changes. No changes to `parser.mly`, `ast.ml`, or `typecheck.ml`.

---

## 3. No-Panic Modules (`opts no_panic`)

### Motivation

The full `Cap(Panic)` retrofit (§4) requires making `Cap(Panic)` explicit at every arithmetic operation site — that is a language-wide migration. The cost is very high. A practical intermediate step: let a module declare that **none of its functions can panic**, enforced by the compiler. This is useful for:

- Embedded / realtime code modules
- Security-critical parsing modules
- Any library that wants to guarantee to its callers "we will never abort"

### Syntax

A module-level `no_panic` directive. The exact surface syntax is a design decision — `"opts"` does not currently exist as a keyword in `lib/lexer/lexer.mll`, so one of three approaches is needed:

- **Option A:** Add `"no_panic"` as a standalone module-level keyword (most visible, easiest to parse, name is self-documenting)
- **Option B:** Add `"opts"` as a new keyword taking an atom-like word argument (`opts no_panic`, `opts no_alloc` for future directives) — more general but requires a two-token production
- **Option C:** Reuse the existing `@[attr]` attribute syntax on modules (`@[no_panic] mod SafeMath do`)

Option B is shown in examples here as the most extensible. Choose at implementation time based on how many module-level directives are expected to accumulate.

```march
mod SafeMath do
  opts no_panic

  fn divide(a : Int, b : Int) : Result(Int, String) do
    if b == 0 do
      Err("division by zero")
    else
      Ok(a / b)
    end
  end

  -- ERROR: array indexing can panic
  fn first(xs : List(Int)) : Int do
    List.nth(xs, 0)   -- List.nth panics on out-of-bounds
  end
end
```

```
Error [no_panic]: `first` in `mod SafeMath` (declared `opts no_panic`) calls
`List.nth`, which can panic on out-of-bounds access.

Use `List.nth_opt` to return `None` instead, or add a bounds check:

  fn first(xs : List(Int)) : Option(Int) do
    List.nth_opt(xs, 0)
  end
```

### What is a "panic site"

The compiler maintains a **panic-surface set** per function: the set of operations that can abort the process at runtime. These are:

| Operation | Panic condition |
|-----------|----------------|
| `a / b`, `a % b` | `b = 0` (integer division by zero) |
| `List.nth(xs, i)` | `i >= length(xs)` |
| `String.slice_bytes(s, lo, hi)` | out-of-bounds |
| `unwrap(None)` / `expect(None, ...)` | value is `None` |
| `assert(false)` | explicit |
| `panic(msg)` | explicit |
| any function that calls a panic site transitively | transitive |

The stdlib ships with a panic-surface annotation for all builtins (a new metadata field on the builtin table). User functions are analyzed transitively.

### Module opts design

`opts no_panic` at the top of a `mod` body applies to all `fn` and `pfn` declarations within. It does not apply to nested modules (which must opt in separately).

The directive is:
- **Checked at call sites within the module:** any function call that can transitively panic is rejected
- **Propagated to callers:** a function exported from a `no_panic` module is annotated as non-panicking in the module's type signature; callers in `no_panic` modules may call it freely

### Relationship to `Cap(Panic)` (§4)

`opts no_panic` is a **module-scoped binary gate** — the whole module either panics or doesn't. `Cap(Panic)` (§4) is a **function-level, granular capability** — individual functions declare what panicking operations they perform.

Both are useful. `opts no_panic` is the simpler, lower-cost stepping stone. The two are compatible: a `no_panic` module is exactly one that contains no functions requiring `Cap(Panic)`.

### Standard library changes

A handful of stdlib functions need non-panicking variants for use in `no_panic` modules. Most already exist (e.g., `List.nth_opt` vs `List.nth`). The ones that don't are:

| Panicking | Non-panicking alternative |
|-----------|--------------------------|
| `unwrap(opt)` | `unwrap_or(opt, default)` / `opt?` (future) |
| `a / b` | `checked_div(a, b) : Option(Int)` (new) |
| `a % b` | `checked_mod(a, b) : Option(Int)` (new) |
| `String.nth(s, i)` | already `String.nth_opt` exists |

`checked_div` and `checked_mod` are new stdlib functions (`stdlib/math.march` or stdlib prelude) that return `None` on `b = 0`.

### Implementation notes

- **New keyword(s).** `"opts"` does not exist in `lib/lexer/lexer.mll`. Whichever surface syntax is chosen (see §Syntax above), the lexer and parser need updating. Option A (`no_panic` keyword) requires one new token; Option B (`opts` + identifier) requires one new token + a two-token production; Option C (`@[no_panic]` attribute) reuses existing attribute machinery if it already exists on modules.
- **AST.** Add `mod_no_panic : bool` flag to the module AST node (or store it via the attribute list if option C is chosen).
- **Type environment.** Propagate the flag into `env` as `in_no_panic_module : bool` during `check_module`, set when processing a module with the directive.
- **Panic-surface table.** New `panic_surface : string list` — a set of builtin function names known to panic (e.g., `"int_div"`, `"list_nth"`, `"unwrap"`, `"assert_"`, `"panic_"`). These map to the internal names used in the eval/codegen builtins (`lib/typecheck/typecheck.ml` builtin table). The table is defined inline in `typecheck.ml` alongside the builtin signatures.
- **Transitive analysis.** During `check_module`, for each fn in a `no_panic` module, walk the function body's `EApp` calls. Any call to a name in `panic_surface` is a violation. Calls to user-defined functions in the same module are checked recursively (they were already validated during their own `check_decl`). Calls to functions from other modules: check whether that module also carries the `no_panic` attribute and whether the function's `panic_surface` was recorded.
- **Error message:** names the specific panic site and suggests the non-panicking alternative (using a suggestion table parallel to `panic_surface`).

**Estimated scope:** ~400 lines (`lexer.mll`, `parser.mly`, `ast.ml`, `typecheck.ml`). No TIR/runtime changes. New stdlib functions: `checked_div`, `checked_mod`.

---

## 4. Full `Cap(Panic)` Hierarchy (Deferred Sub-Spec)

This section sketches the full design for record. It is **not in scope for Phase 3 implementation** — it requires a language-wide migration and its own sub-spec when a concrete use case demands it.

### The capability hierarchy

```
Cap(Panic)
├── Cap(Panic.Arithmetic)    -- integer overflow, division by zero
├── Cap(Panic.Bounds)        -- array/string out-of-bounds
├── Cap(Panic.Assert)        -- assert/invariant failures
└── Cap(Panic.Ffi)           -- undefined behavior from C FFI
```

A second root alongside `Cap(IO)`. The `Cap(Panic)` sub-hierarchy would be added to `io_cap_hierarchy` (`lib/typecheck/typecheck.ml:877`) alongside the existing IO entries. The name `io_cap_hierarchy` is a misnomer at that point, but renaming it is optional cosmetic work.

### The implicit threading problem

The fundamental difficulty: `a / b` does not take a capability parameter today. Making division require `Cap(Panic.Arithmetic)` means either:

1. **Explicit threading**: every expression containing division must take and pass a `Cap(Panic.Arithmetic)`. This is extremely invasive — arithmetic appears everywhere.

2. **Implicit threading**: a new compiler mechanism that propagates a `Cap(Panic)` parameter through the AST, similar to how some languages handle monadic effects without explicit monad syntax.

3. **Effect system integration**: capabilities subsume effects (this was considered for Phase 1 and decided against — see Phase 1 rationale). Revisiting this for `Cap(Panic)` specifically is possible.

Option 1 is impractical for general code. Options 2 and 3 are significant language features. This is why the full retrofit is deferred: the mechanism is the hard problem, not the hierarchy.

### Checked primitives

Regardless of the implicit threading approach, the following non-panicking primitives would be needed:

```march
checked_div(a, b)   : Option(Int)    -- None on b=0
checked_mod(a, b)   : Option(Int)    -- None on b=0
safe_index(xs, i)   : Option(a)      -- None on out-of-bounds
safe_slice(s, l, h) : Option(String) -- None on out-of-bounds
```

Some of these overlap with existing `_opt` variants. The naming convention for Phase 3a (`opts no_panic`) would be `checked_*` for arithmetic, matching the established stdlib convention.

### Path forward

1. Phase 3c (this doc) — `opts no_panic` modules: binary gate, no implicit threading needed
2. Future sub-spec — implicit `Cap(Panic)` threading mechanism design
3. Future sub-spec — language-wide `Cap(Panic)` retrofit with migration guide

Write the sub-spec when a concrete embedded/realtime use case requires fine-grained panic granularity beyond what `opts no_panic` provides.

---

## 5. GADT State Refinement (Exploratory)

### Motivation

With `Handle(R, S)`, the current transition-function model covers the majority of resource lifecycle cases. The one case it cannot handle is **discriminating on state inside a match**:

```march
-- Want: in the Closed arm, h has type Handle(Conn, Closed)
--       in the Open arm,   h has type Handle(Conn, Open)
match current_state do
  Closed ->
    let h2 = open(h)    -- here h : Handle(Conn, Closed) — compile-time guaranteed
    ...
  Open ->
    let (rows, h2) = query(h, sql)   -- here h : Handle(Conn, Open) — compile-time guaranteed
    ...
end
```

This requires GADT-style type refinement: inside the `Closed` arm, `S` in `Handle(Conn, S)` is refined to `Closed`.

### Why it's deferred

GADT refinement requires the type checker to propagate type equalities introduced by constructor patterns into the branch body. The current bidirectional HM checker does not track such equalities. Adding them correctly (avoiding unsoundness) is non-trivial — it's the same mechanism that makes GADTs complex in OCaml and Haskell.

The transition-function model works around this: instead of matching on state, you call transition functions and let linearity enforce the correct sequence. This covers the vast majority of Handle use cases.

### When to pursue

GADT refinement should be added when:
1. The transition-function workaround becomes ergonomically painful in practice (user feedback)
2. A concrete use case requires matching on handle state (not just calling transitions)
3. The type checker architecture is in a state where adding GADT equalities is tractable

Until then, GADT refinement is exploratory — no implementation planned for Phase 3.

---

## 6. Tooling Completions

### `forge cap coverage` (Q5 from Phase 2)

Phase 2 left this open. Two approaches:

**Static analysis (simpler):** Walk the call graph from test entry points; compute the set of capabilities exercised by each test (transitively). Report which capabilities have no test exercising them.

- Pro: no runtime instrumentation, no test framework changes
- Con: imprecise — tests that exercise a capability via a code path that isn't statically reachable from the call graph entry will be missed

**Dynamic instrumentation (more precise):** Insert capability-site counters at compile time when building in `--cap-coverage` mode; aggregate at test completion.

- Pro: precise — actually executed paths
- Con: requires a runtime counter API, test-framework integration, compile-mode flag

**Decision for Phase 3:** Implement static analysis first (`forge cap coverage --static`, default). Add dynamic mode as `--dynamic` in a follow-up once the static version proves its value.

**Estimated scope:** ~300 lines in `forge/lib/cmd_cap.ml` for static analysis; call graph already partially built during compilation.

### Capability flow in LSP (Phase 2f complement)

Phase 2f shipped capability hover and `via` completions. Remaining LSP items:

- **Find-references on `Cap(X)`**: show all functions requiring it, all `needs X` declarations, all `cap_narrow` sites producing it
- **Go-to-definition on `proof cap Foo`**: navigate to the declaring module's `proof cap` statement
- **Inlay hints**: show implicit `Cap(X)` requirements next to call sites inside capability-constrained functions

These are incremental LSP additions, each ~100–200 lines in `lsp/`.

---

## 7. Implementation Roadmap

### Phase 3a — Explicit bounded type parameters (medium cost)

- `[S : ConnState, P : Policy]` syntax on fn/pfn declarations
- Parser, AST, typecheck
- Error messages: bound violation with the inferred type and the declared bound
- Tests: ~8 new capability tests

**Estimated scope:** ~250 lines. No eval/TIR/runtime changes.

### Phase 3b — Policy-tag DCE pass (medium cost)

- New `lib/tir/policy_dce.ml` audit pass
- Policy table: `Realtime → [NoAlloc; NoIO; NoPanic]`, `NoAlloc → [NoAlloc]`, etc.
- Audit mode: report violations; DCE mode deferred
- Tests: ~6 new capability tests (violations detected, clean functions accepted)

**Estimated scope:** ~300 lines.

### Phase 3c — No-panic modules (medium cost)

- `opts no_panic` module directive
- Panic-surface metadata on builtins
- Transitive panic analysis in `check_module`
- Error messages with non-panicking alternatives
- New stdlib: `checked_div`, `checked_mod`
- Tests: ~10 new capability tests

**Estimated scope:** ~400 lines + 2 stdlib functions.

### Phase 3d — Full `Cap(Panic)` hierarchy (high cost, deferred)

Out of scope for Phase 3. Requires a separate sub-spec on implicit capability threading. Write when a concrete embedded/realtime use case demands it.

### Phase 3e — GADT state refinement (exploratory, deferred)

Out of scope for Phase 3. Requires significant type checker extension. Defer until user demand justifies the complexity.

### Phase 3f — Tooling completions (ongoing)

- `forge cap coverage --static`: ~300 lines in `forge/`
- LSP find-references for `Cap(X)`: ~150 lines in `lsp/`
- LSP go-to-definition for `proof cap`: ~100 lines in `lsp/`
- LSP inlay hints for capability requirements: ~200 lines in `lsp/`

---

## 8. What This Does Not Change

- **Phase 1 and Phase 2 enforcement** — all existing checks remain unchanged
- **`Handle(R, S)` and `Tagged(X, T)` semantics** — Phase 3a adds syntax for expressing constraints that were already implicit; it does not change what's valid
- **`opts no_panic` is opt-in** — no existing code breaks; modules without the directive behave identically
- **The runtime** — no runtime changes in Phase 3. All new mechanisms are compile-time

---

## 9. Open Questions

**Q1 — `opts` keyword scope:** Is `opts` the right syntax for module directives? Does an `opts` keyword already exist in the lexer? If not, consider `pragma`, `use opts`, or a `#[no_panic]`-style attribute syntax. Check `lexer.mll` before implementation.

**Q2 — Bound syntax for TNat:** `[N : TNat]` bounds a type variable to be a type-level natural. Is this the same mechanism as `[S : ConnState]` (both are "S must be a value-in this type")? Or is `TNat` special (it's a kind, not a type)? Decide at implementation time.

**Q3 — `opts no_panic` and FFI:** If a `no_panic` module calls a C FFI function, should that be a panic site (`Cap(Panic.Ffi)`)? Probably yes — C can abort. Phase 3c can treat any FFI call as a panic site in `no_panic` modules; the programmer must wrap it in a `no_ffi_panic_guard` or similar.

**Q4 — Panic surface for stdlib functions:** The panic-surface metadata table must be accurate. A conservative approach (anything that calls `panic` or `assert` is a panic site) is correct but may be too noisy. Consider letting stdlib functions opt out via annotation when they are provably non-panicking despite calling internal assert-style helpers.

**Q5 — Static cap coverage precision:** Static analysis over the call graph will report "not covered" for capabilities only reachable via branches that are not taken in any test. This may produce false negatives for capabilities gated behind feature flags or rarely-exercised paths. Document this limitation clearly in the output.
