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

### 3.1 Motivation

The full `Cap(Panic)` retrofit (§4) requires making `Cap(Panic)` explicit at every arithmetic operation site — that is a language-wide migration. The cost is very high. A practical intermediate step: let a module declare that **none of its functions can panic**, enforced by the compiler. This is useful for:

- Embedded / realtime code modules
- Security-critical parsing modules
- Any library that wants to guarantee to its callers "we will never abort"

Unlike Phase 3b's TIR-level audit (which operates after source information is gone), Phase 3c enforces the invariant **at typecheck time**, giving errors with precise source spans that point to the exact call site.

---

### 3.2 Syntax Decision

**Choose Option B: `opts` keyword + directive-name identifier.**

Rationale: `PROOFCAP` and `ALWAYSLINEAR` are precedents for single-token compound keywords, but they name unique constructs. `opts` is a meta-level keyword for *module options* — a namespace that can grow (`opts no_alloc`, `opts no_io`) without adding more compound keywords. Option A (`no_panic` alone) is not extensible. Option C (`@[no_panic]` attribute on `mod`) reuses the function-attribute mechanism which carries different semantics and requires AST changes to the module node rather than a new declaration variant.

**Verified:** `opts` does not appear in `lib/lexer/lexer.mll`'s keyword table (line 75–86). `no_panic` is not a keyword; it will parse as `LOWER_IDENT "no_panic"`.

**Surface syntax:**

```march
mod SafeMath do
  opts no_panic

  fn divide(a : Int, b : Int) : Result(Int, String) do
    if b == 0 do
      Err("division by zero")
    else
      Ok(a / b)   -- ERROR: / can panic when b = 0
    end
  end

  fn first(xs : List(Int)) : Option(Int) do
    List.nth_opt(xs, 0)   -- OK: nth_opt returns None, not panic
  end

  fn bad_first(xs : List(Int)) : Int do
    List.nth(xs, 0)   -- ERROR: nth panics on out-of-bounds
  end
end
```

`opts no_panic` must appear inside a `mod ... do ... end` body, as a declaration alongside `fn`, `type`, `needs`, etc. It applies to all `fn` and `pfn` declarations in the **same** `mod` body; nested `mod` blocks are checked independently and must opt in separately.

Multiple opts on the same module are not supported in Phase 3c (only `no_panic` exists); the `string list` in `DOpts` is forward-looking for when `opts no_alloc` etc. are added.

---

### 3.3 What Is a "Panic Site"

There are two categories:

**Category 1 — Direct builtin calls.** These are bare names that appear as `EVar name` in the AST. After desugar, operators like `/` and `%` appear as `EApp(EVar "/", [a; b])`.

| Name in AST | Panic condition |
|-------------|----------------|
| `/` | integer divisor is zero |
| `%` | integer divisor is zero |
| `int_div` | divisor is zero |
| `int_mod` | divisor is zero |
| `int_div_euclid` | divisor is zero |
| `int_mod_euclid` | divisor is zero |
| `panic` | always (explicit abort) |
| `panic_` | always (internal panic builtin) |
| `todo_` | always (todo! marker) |
| `unreachable_` | always (unreachable! marker) |

Note: `assert` is desugared to `if not cond do panic_ "..." end` by `desugar.ml` before typecheck — it does not appear as an `EApp` node. It is caught through `panic_` in the desugared body.

**Category 2 — Stdlib function calls.** These appear as `EApp(EField(EVar "Module", "fn"), args)` in the AST (March represents qualified calls as field access on the module name). They are stdlib functions whose bodies call `panic_` or `int_div`/etc.

| Qualified name | Panic condition |
|----------------|----------------|
| `List.nth` | index out of bounds |
| `List.hd` | called on `Nil` |
| `List.tl` | called on `Nil` |
| `List.head` | called on `Nil` |
| `List.last` | called on `Nil` |
| `List.min_elt` | called on empty |
| `List.max_elt` | called on empty |
| `Option.unwrap` | called on `None` |
| `Option.expect` | called on `None` |
| `Result.unwrap` | called on `Err` |
| `Result.expect` | called on `Err` |
| `Result.unwrap_err` | called on `Ok` |
| `Array.get` | index out of bounds |
| `Array.set` | index out of bounds |
| `String.slice_bytes` | range out of bounds |
| `String.nth` | index out of bounds |
| `NativeArray.get` | index out of bounds |
| `NativeArray.set` | index out of bounds |

**Prelude-exported names** (`unwrap`, `expect`, `head`, `tail`) are auto-imported into every module's namespace and appear as bare `EVar` names — **not** qualified. They must be in the direct-builtin table:

| Name in AST | Panic condition |
|-------------|----------------|
| `unwrap` | called on `None` |
| `expect` | called on `None` |
| `head` | called on `Nil` |
| `tail` | called on `Nil` |
| `last` | called on `Nil` |

**Note on transitive stdlib calls.** This list is **authoritative and static** — it covers stdlib functions known to panic. We do not walk stdlib bodies at typecheck time (they are compiled modules). If a stdlib function is missing from this list and panics, the static check will not catch it. The list should be kept in sync with stdlib evolution.

---

### 3.4 Detection Strategy (AST-Level Walk)

Because Phase 3c runs at typecheck time (not TIR), we have access to source spans in `EApp` nodes. The body of each function clause is `fc_body : Ast.expr`. The relevant AST forms:

```ocaml
type expr =
  | EApp   of expr * expr list * span    (* f(x, y) — span covers the call site *)
  | EVar   of name                        (* bare name — name.span is the id's position *)
  | EField of expr * name * span          (* expr.field *)
  | EBlock of expr list * span
  | ELet   of binding * span              (* let x = e; binding.bind_expr is the rhs *)
  | EMatch of expr * branch list * span   (* branch.branch_body is each arm's body *)
  | EIf    of expr * expr * expr * span   (* cond, then_, else_ *)
  | EPipe  of expr * expr * span          (* desugared before typecheck — rarely present *)
  | ELetFn of name * param list * ty option * expr * span
  | ELetQ  of pattern * expr * expr * span  (* let? p = rhs; body *)
  ...
```

**Two call patterns to detect:**

**Pattern 1: Direct builtin** — `EApp(EVar {txt = name; span = fn_span}, args, _)` where `name ∈ panic_surface_direct`. The error span is `fn_span` (the function name's position).

**Pattern 2: Qualified stdlib** — `EApp(EField(EVar {txt = mod_name}, {txt = fn_name; span = fn_span}), args, _)` where `mod_name ^ "." ^ fn_name ∈ panic_surface_stdlib`. The error span is `fn_span` (the field name's position).

**Pattern 3: Local function (transitive)** — `EApp(EVar {txt = name; span = fn_span}, args, _)` where `name ∈ locally_panicky_set`. See §3.6.4 for the fixpoint that builds this set.

**Recursive walk of all expr forms.** For the walk itself, the standard recursive pattern:

```ocaml
let rec calls_in_expr (acc : (string * Ast.span) list) (e : Ast.expr)
    : (string * Ast.span) list =
  match e with
  | Ast.EApp (Ast.EVar fn_name, args, _) ->
    let acc = (fn_name.txt, fn_name.span) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (Ast.EField (Ast.EVar mod_name, fn_name, _), args, _) ->
    let qname = mod_name.txt ^ "." ^ fn_name.txt in
    let acc = (qname, fn_name.span) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (f, args, _) ->
    List.fold_left calls_in_expr (calls_in_expr acc f) args
  | Ast.EBlock (es, _) ->
    List.fold_left calls_in_expr acc es
  | Ast.ELet (b, _) ->
    calls_in_expr acc b.Ast.bind_expr
  | Ast.EMatch (scrut, arms, _) ->
    let acc = calls_in_expr acc scrut in
    List.fold_left (fun a arm ->
      let a = Option.fold ~none:a ~some:(calls_in_expr a) arm.Ast.branch_guard in
      calls_in_expr a arm.Ast.branch_body) acc arms
  | Ast.EIf (cond, then_, else_, _) ->
    calls_in_expr (calls_in_expr (calls_in_expr acc cond) then_) else_
  | Ast.EField (e, _, _) -> calls_in_expr acc e
  | Ast.EPipe (a, b, _) -> calls_in_expr (calls_in_expr acc a) b
  | Ast.ELetFn (_, _, _, body, _) -> calls_in_expr acc body
  | Ast.ELetQ (_, rhs, body, _) ->
    calls_in_expr (calls_in_expr acc rhs) body
  | Ast.ELit _ | Ast.EVar _ -> acc
  | _ -> acc
```

This collects **all** `(called_name, span)` pairs in the expression tree. The caller then filters by the panic-surface sets.

---

### 3.5 Intra-Module Transitive Analysis

Within a `no_panic` module, if function `g` calls `h` and `h` directly calls `int_div`, then `g` is also a panic site. The fixpoint algorithm:

1. **Seed**: for each `fn_def` in the module, check whether any name in its collected call list (`calls_in_expr`) is in `panic_surface_direct ∪ panic_surface_prelude ∪ panic_surface_stdlib`. If yes, it's a **direct violator**.
2. **Expand**: for each `fn_def` not yet in the panicky set, check whether any name in its call list is the name of a function already in the panicky set. If yes, add it.
3. **Repeat** until the set no longer grows. Terminates because the module has finitely many functions.

This is the same fixpoint shape as `Policy_dce.panicky_fns_of_module` in Phase 3b, but operating on the AST rather than TIR.

**For error reporting**, we want the specific call site span. The walk returns `(string * Ast.span) list`, so for a direct violator we find the first entry whose name is in the panic surface and use its span. For transitive violators, we use the span of the call to the (transitively panicky) callee.

---

### 3.6 Cross-Module Treatment

Phase 3c uses a **conservative but practical** cross-module policy:

1. **Stdlib functions** — handled by the explicit panic-surface tables (§3.3). Functions not in the table are assumed safe. This is complete for the curated stdlib; new panicking stdlib functions must be added to the table manually.

2. **Functions from other `no_panic` modules** — treated as **safe**. If module `SafeLib` declares `opts no_panic`, its exported functions passed the same check and are guaranteed panic-free. The typecheck env for the current module accumulates `no_panic_modules : StringSet.t` from previously-checked modules (via `env.module_caps` analogy; see §3.6.3).

3. **Functions from non-`no_panic` user modules** — treated as **potentially panicking** and reported as a violation. This is conservative: a helper in a non-`no_panic` module *might* be panic-free, but we cannot prove it statically. The error message explicitly says "function from non-`no_panic` module — mark that module `opts no_panic` or use a different API."

4. **FFI extern functions** — treated as **potentially panicking**. C code can call `abort()` or signal handlers. If a `no_panic` module uses an extern, it gets the same cross-module conservative error. (See §3.8 for the escape hatch.)

---

### 3.7 Implementation

#### 3.7.1 Lexer changes (`lib/lexer/lexer.mll`)

Add `"opts"` to the keyword table (at lines 75–86, after `"via"`):

```ocaml
("opts", OPTS);
```

Add the `OPTS` token declaration in `parser.mly`'s `%token` list.

No changes to the main `token` rule — the keyword table lookup handles it.

**~1 line changed.**

---

#### 3.7.2 Parser changes (`lib/parser/parser.mly`)

Add to the `%token` list:

```
%token OPTS
```

Add a new nonterminal after `proof_cap_decl`:

```
opts_decl:
  | OPTS; name = lower_name
    { DOpts ([name.txt], mk_span ($loc)) }
```

Add to the `decl` alternatives (alongside `d = proof_cap_decl`):

```
| d = opts_decl { d }
```

**Parser conflict analysis:** After `OPTS`, the only valid next token is `LOWER_IDENT` (a directive name). `OPTS` does not appear anywhere else in the grammar. No LALR(1) conflict is introduced — `OPTS` is a fresh keyword that the shift/reduce automaton has not seen before, so it creates a new unambiguous production.

**~8 lines changed.**

---

#### 3.7.3 AST changes (`lib/ast/ast.ml`)

Add to the `decl` type (after `DProofCap`, around line 155):

```ocaml
| DOpts of string list * span
  (** Module-level directives: [`"no_panic"`] from `opts no_panic`.
      The list allows multiple future directives; Phase 3c only uses `"no_panic"`. *)
```

**~3 lines changed.**

---

#### 3.7.4 Typecheck env changes (`lib/typecheck/typecheck.ml`)

Add two fields to `type env`:

```ocaml
type env = {
  (* ... all existing fields ... *)
  no_panic_mod : bool;
  (** True when the module currently being checked has `opts no_panic`.
      Set by [check_decl] on [DOpts ["no_panic"]]; read by [check_no_panic_module]. *)
  no_panic_modules : string list;
  (** Names of modules (siblings/imports) that have been verified as [opts no_panic].
      Functions from these modules are treated as safe in [check_no_panic_module]. *)
}
```

Initialize to `false` / `[]` in `make_env`:

```ocaml
let make_env errors type_map = {
  (* ... existing fields ... *)
  no_panic_mod = false;
  no_panic_modules = [];
}
```

**~6 lines changed.**

---

#### 3.7.5 Panic-surface tables (new, in `typecheck.ml`)

Define just before `check_no_panic_module` (around line 6625):

```ocaml
module StringSet = Set.Make(String)

(** Direct builtin/operator names that constitute a panic site.
    These appear as [EVar name] in the AST (operators are desugared to EApp+EVar by parser). *)
let panic_surface_direct : StringSet.t = StringSet.of_list [
  "/"; "%"; "int_div"; "int_mod"; "int_div_euclid"; "int_mod_euclid";
  "panic"; "panic_"; "todo_"; "unreachable_";
]

(** Prelude-exported names that can panic — imported bare (no qualification). *)
let panic_surface_prelude : StringSet.t = StringSet.of_list [
  "unwrap"; "expect"; "head"; "tail"; "last";
]

(** Qualified stdlib names (Module.fn) that can panic.
    These appear as [EApp(EField(EVar mod, fn), _)] in the AST.
    Keep this in sync with stdlib evolution. *)
let panic_surface_stdlib : StringSet.t = StringSet.of_list [
  "List.nth"; "List.hd"; "List.tl"; "List.head"; "List.last";
  "List.min_elt"; "List.max_elt";
  "Option.unwrap"; "Option.expect";
  "Result.unwrap"; "Result.expect"; "Result.unwrap_err";
  "Array.get"; "Array.set";
  "String.slice_bytes"; "String.nth";
  "NativeArray.get"; "NativeArray.set";
]

let panic_surface_all_direct : StringSet.t =
  StringSet.union panic_surface_direct panic_surface_prelude
```

**~28 lines added.**

---

#### 3.7.6 `calls_in_expr` utility

```ocaml
(** Collect all (called_name, span) pairs from an expression tree.
    Returns every function name that appears as the callee of an EApp,
    whether direct (EVar) or qualified (EField). *)
let rec calls_in_expr (acc : (string * Ast.span) list) (e : Ast.expr)
    : (string * Ast.span) list =
  match e with
  | Ast.EApp (Ast.EVar fn_name, args, _) ->
    let acc = (fn_name.txt, fn_name.span) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (Ast.EField (Ast.EVar mod_name, fn_name, _), args, _) ->
    let qname = mod_name.txt ^ "." ^ fn_name.txt in
    let acc = (qname, fn_name.span) :: acc in
    List.fold_left calls_in_expr acc args
  | Ast.EApp (f, args, _) ->
    List.fold_left calls_in_expr (calls_in_expr acc f) args
  | Ast.EBlock (es, _) ->
    List.fold_left calls_in_expr acc es
  | Ast.ELet (b, _) ->
    calls_in_expr acc b.Ast.bind_expr
  | Ast.EMatch (scrut, arms, _) ->
    let acc = calls_in_expr acc scrut in
    List.fold_left (fun a arm ->
      let a = Option.fold ~none:a ~some:(calls_in_expr a) arm.Ast.branch_guard in
      calls_in_expr a arm.Ast.branch_body) acc arms
  | Ast.EIf (cond, then_, else_, _) ->
    calls_in_expr (calls_in_expr (calls_in_expr acc cond) then_) else_
  | Ast.EField (inner, _, _) -> calls_in_expr acc inner
  | Ast.EPipe (a, b, _) -> calls_in_expr (calls_in_expr acc a) b
  | Ast.ELetFn (_, _, _, body, _) -> calls_in_expr acc body
  | Ast.ELetQ (_, rhs, body, _) ->
    calls_in_expr (calls_in_expr acc rhs) body
  | Ast.ELit _ | Ast.EVar _ -> acc
  | _ -> acc
```

**~32 lines added.**

---

#### 3.7.7 `check_decl` handler for `DOpts`

In `check_decl` (around line 6093, after `DProofCap` handler):

```ocaml
| Ast.DOpts (opts, _sp) ->
  (* Phase 3c: no_panic module directive *)
  if List.mem "no_panic" opts then
    { env with no_panic_mod = true }
  else begin
    (* Unknown opts names are silently ignored for forward compatibility.
       Future directives (no_alloc, no_io) will be handled here. *)
    env
  end
```

**~8 lines added.**

---

#### 3.7.8 `check_no_panic_module` — the main analysis function

This function runs after Pass 2. It:

1. Collects all function clauses from top-level `DFn` declarations (not nested mods)
2. Builds a `fn_calls` map: function name → (string * span) list of all callees
3. Seeds the `panicky` set from direct panic-surface hits
4. Runs fixpoint expansion to find transitive panicky functions within the module
5. Reports one error per violating function, pointing to the first panic site

```ocaml
(** [check_no_panic_module errors env decls] validates that none of the
    top-level [fn]/[pfn] declarations in [decls] call a panic-surface operation,
    directly or transitively within this module.
    
    Called only when [env.no_panic_mod = true], after Pass 2 of [check_module_core]. *)
let check_no_panic_module (errors : Err.ctx) (env : env) (decls : Ast.decl list) : unit =
  (* Step 1: collect function names and their call lists *)
  let fn_entries : (string * (string * Ast.span) list * Ast.span) list =
    List.filter_map (fun d ->
      match d with
      | Ast.DFn (def, fn_span) ->
        let all_calls =
          List.fold_left (fun acc clause ->
            calls_in_expr acc clause.Ast.fc_body
          ) [] def.Ast.fn_clauses
        in
        Some (def.Ast.fn_name.txt, all_calls, fn_span)
      | _ -> None
    ) decls
  in
  (* Helper: the set of locally-defined function names *)
  let local_fns =
    List.fold_left (fun s (name, _, _) -> StringSet.add name s)
      StringSet.empty fn_entries
  in
  (* Step 2: decide if a called name is a panic site
     - in panic_surface_direct/prelude: definitely panicky
     - in panic_surface_stdlib: definitely panicky
     - a local fn name (transitive — resolved during fixpoint below): skip here
     - a name from a known no_panic module: safe
     - anything else (external user fn / extern): conservatively panicky *)
  let no_panic_mod_names = StringSet.of_list env.no_panic_modules in
  let is_direct_panic_site name =
    StringSet.mem name panic_surface_all_direct
    || StringSet.mem name panic_surface_stdlib
  in
  let is_external_unknown name =
    (* Not local, not in panic surface, not a no_panic module export *)
    not (StringSet.mem name local_fns)
    && not (is_direct_panic_site name)
    && not (StringSet.exists (fun mod_name ->
              let prefix = mod_name ^ "." in
              String.length name >= String.length prefix
              && String.sub name 0 (String.length prefix) = prefix
            ) no_panic_mod_names)
    (* Bare (unqualified) names that are NOT in the panic surface or local_fns
       are usually stdlib safe functions (List.map, String.concat, etc. imported
       as bare names). For now, treat unknown bare names as safe. *)
    && String.contains name '.'  (* only flag qualified unknown names *)
  in
  (* Step 3: seed panicky set from direct violations *)
  let seed =
    List.fold_left (fun (panicky, site_map) (fn_name, calls, _span) ->
      match List.find_opt (fun (n, _sp) ->
        is_direct_panic_site n || is_external_unknown n
      ) calls with
      | Some (site_name, site_span) ->
        (StringSet.add fn_name panicky,
         StrMap.add fn_name (site_name, site_span, `Direct) site_map)
      | None ->
        (panicky, site_map)
    ) (StringSet.empty, StrMap.empty) fn_entries
  in
  let seed_panicky, seed_site_map = seed in
  (* Step 4: fixpoint expansion — find transitively panicky local functions *)
  let rec fixpoint panicky site_map =
    let (panicky', site_map') =
      List.fold_left (fun (p, sm) (fn_name, calls, _span) ->
        if StringSet.mem fn_name p then (p, sm)
        else
          match List.find_opt (fun (n, _sp) ->
            StringSet.mem n p && StringSet.mem n local_fns
          ) calls with
          | Some (callee_name, callee_span) ->
            (StringSet.add fn_name p,
             StrMap.add fn_name (callee_name, callee_span, `Transitive) sm)
          | None -> (p, sm)
      ) (panicky, site_map) fn_entries
    in
    if StringSet.cardinal panicky' = StringSet.cardinal panicky then
      (panicky', site_map')
    else
      fixpoint panicky' site_map'
  in
  let (all_panicky, site_map) = fixpoint seed_panicky seed_site_map in
  (* Step 5: report one error per violating function *)
  List.iter (fun (fn_name, _calls, fn_span) ->
    if StringSet.mem fn_name all_panicky then begin
      match StrMap.find_opt fn_name site_map with
      | None -> ()
      | Some (site_name, site_span, kind) ->
        let mod_name = env.current_module in
        let msg = match kind with
          | `Direct ->
            let suggestion = panic_surface_suggestion site_name in
            Printf.sprintf
              "`%s` in `mod %s` (declared `opts no_panic`) calls `%s`, which can panic.%s"
              fn_name mod_name site_name suggestion
          | `Transitive ->
            Printf.sprintf
              "`%s` in `mod %s` (declared `opts no_panic`) transitively calls `%s`, \
               which can panic."
              fn_name mod_name site_name
        in
        Err.error errors ~span:site_span msg
    end
  ) fn_entries
```

**~80 lines added.**

---

#### 3.7.9 Suggestion table for error messages

A small table mapping each panic site to its non-panicking alternative:

```ocaml
let panic_surface_suggestion : string -> string = function
  | "/" | "%" | "int_div" | "int_mod" | "int_div_euclid" | "int_mod_euclid" ->
    "\n\nUse `Math.checked_div` or `Math.checked_mod` to return `None` instead of panicking."
  | "List.nth" ->
    "\n\nUse `List.nth_opt` to return `Option(a)` instead of panicking on out-of-bounds."
  | "List.hd" | "List.head" | "head" ->
    "\n\nUse `List.head_opt` (or match on `Cons`/`Nil` directly) to avoid panicking on empty."
  | "List.tl" | "List.tail" | "tail" ->
    "\n\nUse `List.tail_opt` or match on `Nil` to avoid panicking on empty."
  | "unwrap" | "Option.unwrap" ->
    "\n\nUse `unwrap_or(opt, default)` or `match opt do Some(x) -> ... | None -> ... end`."
  | "expect" | "Option.expect" ->
    "\n\nUse `unwrap_or` or an explicit match to handle the `None` case."
  | "Result.unwrap" | "Result.expect" ->
    "\n\nUse `Result.unwrap_or` or match on `Ok`/`Err` to handle the error case."
  | "Array.get" | "Array.set" | "NativeArray.get" | "NativeArray.set" ->
    "\n\nBounds-check the index before access, or use a bounds-checked variant."
  | "String.slice_bytes" | "String.nth" ->
    "\n\nBounds-check the index/range before access."
  | "panic" | "panic_" ->
    "\n\nReturn an error value (`Result`, `Option`) instead of calling `panic`."
  | "todo_" ->
    "\n\nImplement the body instead of using `todo!`, or remove the `opts no_panic` directive."
  | "unreachable_" ->
    "\n\nAdd a proof comment if this branch is truly unreachable, or handle it explicitly."
  | _ -> ""
```

**~28 lines added.**

---

#### 3.7.10 Integration in `check_module_core`

In `check_module_core`, after the `check_module_needs` call (line 6845):

```ocaml
let final_env = List.fold_left check_decl pre_env (reorder_decls m.Ast.mod_decls) in
(* Validate capability declarations for the top-level module *)
check_module_needs final_env m.Ast.mod_name m.Ast.mod_decls;
(* NEW: validate no_panic invariant if declared *)
if final_env.no_panic_mod then
  check_no_panic_module errors final_env m.Ast.mod_decls;
(* Warn about any unused imports or aliases *)
warn_unused_imports final_env;
```

**~3 lines added.**

---

#### 3.7.11 Propagating `no_panic_modules` to sibling modules

When a `DMod` block is fully checked and its `final_env.no_panic_mod = true`, record the module name so sibling modules can call it safely. This is analogous to how `module_caps` propagates IO requirements:

In `check_decl` for `DMod` (around the point where the inner module's env is merged back):

```ocaml
(* After inner check_module_core returns final_inner_env: *)
let env =
  if final_inner_env.no_panic_mod then
    { env with no_panic_modules = mname.txt :: env.no_panic_modules }
  else env
in
```

This is a localized addition to the existing `DMod` handling. **~5 lines added.**

---

### 3.8 Error Message Format

**Direct violation (call to panic-surface builtin/stdlib):**

```
Error: `divide` in `mod SafeMath` (declared `opts no_panic`) calls `/`, which can panic.

Use `Math.checked_div` or `Math.checked_mod` to return `None` instead of panicking.
```

The span points to the `/` token inside the function body — the operator's position in source.

**Direct violation (stdlib function):**

```
Error: `first` in `mod SafeMath` (declared `opts no_panic`) calls `List.nth`, which can panic.

Use `List.nth_opt` to return `Option(a)` instead of panicking on out-of-bounds.
```

The span points to `nth` in `List.nth(xs, 0)`.

**Transitive violation:**

```
Error: `process_list` in `mod SafeMath` (declared `opts no_panic`) transitively calls
`find_elem`, which can panic.
```

The span points to the `find_elem` call site inside `process_list`. The user then reads `find_elem` to find the direct violation there.

**Conservative cross-module violation:**

```
Error: `run` in `mod SafeMath` (declared `opts no_panic`) calls `Parser.parse`,
which is in a non-`no_panic` module and may panic.

Mark `mod Parser` with `opts no_panic` to verify it is panic-free, or use a
panic-free alternative.
```

---

### 3.9 Stdlib Additions

Add to `stdlib/math.march` (or the prelude if broadly useful):

```march
doc "Divide `a` by `b`, returning `None` if `b` is zero."
fn checked_div(a : Int, b : Int) : Option(Int) do
  if b == 0 do None else Some(a / b) end
end

doc "Compute `a % b`, returning `None` if `b` is zero."
fn checked_mod(a : Int, b : Int) : Option(Int) do
  if b == 0 do None else Some(a % b) end
end
```

Note: `checked_div` and `checked_mod` are defined in the `Math` module which is **not** `opts no_panic` (it uses `/` and `%` internally in the safe branch). Callers from a `no_panic` module call `Math.checked_div(a, b)` — the qualified name is not in `panic_surface_stdlib`, so no violation is reported.

**~10 lines added to `stdlib/math.march`.**

---

### 3.10 FFI Escape Hatch

A `no_panic` module may need to call a C extern that provably cannot panic (e.g., a pure math function). Phase 3c flags all extern calls conservatively. The workaround: define a thin wrapper module:

```march
-- In a NON-no_panic wrapper module:
mod UnsafeMathFFI do
  extern fn c_sqrt(x : Float) : Float
  fn safe_sqrt(x : Float) : Float do c_sqrt(x) end
end

-- In the no_panic module:
mod SafeCalc do
  opts no_panic
  -- UnsafeMathFFI is not no_panic, so calls to it would be flagged.
  -- To fix: mark UnsafeMathFFI as no_panic too.
end
```

Full FFI safety in `no_panic` modules requires the user to also mark the wrapper module `opts no_panic`. If the wrapper calls an extern, the extern itself is the final boundary — the user accepts responsibility. Phase 3c cannot verify C code; it only verifies that the March wrapper is panic-free at the March level.

---

### 3.11 Relationship to Phase 3b (Policy-Tag DCE)

Phase 3b catches policy violations on **TIR-specialized functions** (after monomorphization), with no source spans. Phase 3c catches panic sites on **`no_panic` module functions** at **typecheck time**, with precise source spans.

They are **complementary and non-redundant**:

| Dimension | Phase 3b | Phase 3c |
|-----------|----------|----------|
| Granularity | Per-function via `Tagged(_, NoPanic)` | Per-module via `opts no_panic` |
| Analysis level | TIR (after lower + mono) | AST (typecheck time) |
| Source spans | No — TIR has no spans | Yes — AST retains spans |
| Transitive analysis | Via `panicky_fns_of_module` fixpoint over stdlib bodies | Static table + intra-module fixpoint |
| Stdlib coverage | Picks up `unwrap` transitively via TIR bodies | Static `panic_surface_stdlib` table |
| Use case | Library APIs with policy-parameterized functions | Entire module guarantees |

A module can use both: mark it `opts no_panic` AND have some functions take `Tagged(_, NoPanic)` parameters. The two checks are independent.

---

### 3.12 Estimated Implementation Scope

| File | Change | ~Lines |
|------|--------|--------|
| `lib/lexer/lexer.mll` | Add `"opts"` to keyword table | +1 |
| `lib/parser/parser.mly` | `%token OPTS`, `opts_decl` production, add to `decl` list | +8 |
| `lib/ast/ast.ml` | Add `DOpts of string list * span` to `decl` type | +3 |
| `lib/typecheck/typecheck.ml` | `panic_surface_*` tables, `calls_in_expr`, `panic_surface_suggestion`, `check_no_panic_module`, `check_decl DOpts` handler, env fields (`no_panic_mod`, `no_panic_modules`), integration in `check_module_core` and `DMod` handler | +175 |
| `stdlib/math.march` | `checked_div`, `checked_mod` | +10 |
| `test/test_compiler.ml` | ~12 new tests in `no_panic` suite | +120 |
| **Total** | | **~317 lines** |

No eval, TIR, codegen, JIT, or runtime changes. The analysis is entirely in `typecheck.ml` and fires before lowering.

The four big blocks in `typecheck.ml`:
- Panic-surface tables + `calls_in_expr`: ~65 lines
- `panic_surface_suggestion`: ~28 lines
- `check_no_panic_module`: ~80 lines
- Env fields + `check_decl` handler + integration hooks: ~15 lines

---

### 3.13 Test Cases (~12 new tests, new `no_panic` suite in `test/test_compiler.ml`)

| # | Description | Expected |
|---|-------------|---------|
| 1 | `opts no_panic` parses correctly (no other decls) | no error |
| 2 | Non-`no_panic` module with `a / b` | no error |
| 3 | `no_panic` module with `a / b` | error at `/` site |
| 4 | `no_panic` module with `a % b` | error at `%` site |
| 5 | `no_panic` module with explicit `panic("msg")` | error at `panic` site |
| 6 | `no_panic` module calling `List.nth` | error at `nth` site |
| 7 | `no_panic` module calling `List.nth_opt` | no error |
| 8 | `no_panic` module calling `Math.checked_div` | no error |
| 9 | `no_panic` module with `unwrap(None)` pattern | error at `unwrap` site |
| 10 | `no_panic` module: helper `h` calls `int_div`, `g` calls `h` | error on both (transitive) |
| 11 | Two sibling `no_panic` modules calling each other | no error |
| 12 | `no_panic` module calling non-`no_panic` user module | error (conservative) |

Tests 1–9 use the AST-direct testing helper pattern (build a synthetic `module_` and call `check_module_core`). Tests 10–12 require multi-function modules and are written as string-based round-trip tests that run the full compiler pipeline on a `.march` snippet.

---

### 3.14 Known Limitations and Future Work

**1. Conservative cross-module check.** Functions from user modules without `opts no_panic` are treated as potentially panicking. This means a `no_panic` module cannot call any external helper unless that helper's module also declares `opts no_panic`. In practice, users structure `no_panic` code in cohesive modules and mark all dependencies accordingly.

**2. Static stdlib table.** The `panic_surface_stdlib` table is manually maintained. If a new stdlib function panics and isn't added to the table, Phase 3c will not catch it. Mitigation: add a linter CI check that runs Phase 3b's TIR-level analysis over stdlib (which DOES pick up transitive panics) and cross-references the static table.

**3. Value-range insensitivity.** If the programmer knows `b != 0` statically (e.g., from a match arm), `a / b` is still flagged. Phase 3c is purely syntactic. Callers must use `checked_div` and pattern-match the result, even when the non-zero invariant is locally obvious.

**4. `todo_` in stub functions.** Using `todo_` (or `panic`) in a stub function body that will never be called generates a false positive. The escape: remove `opts no_panic` from modules under active development and add it back when the module is complete.

**5. Nested mod scoping.** `opts no_panic` on an outer `mod` does NOT apply to inner `mod` blocks. Each must declare independently. This is intentional — nested modules may have different purity requirements — but can surprise users who expect the outer directive to propagate.

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

**Spec complete** — see §3 above for full implementation details.

- `opts no_panic` module directive (Option B: `OPTS` keyword + `LOWER_IDENT` directive name)
- `DOpts of string list * span` added to `Ast.decl`
- `no_panic_mod : bool` + `no_panic_modules : string list` added to typecheck `env`
- `panic_surface_direct`, `panic_surface_prelude`, `panic_surface_stdlib` tables in `typecheck.ml`
- `calls_in_expr` AST walk + `check_no_panic_module` with seed+fixpoint transitive analysis
- Error messages at call-site span with non-panicking alternatives (`panic_surface_suggestion`)
- Conservative cross-module check: non-`no_panic` user modules flagged; `no_panic` siblings safe
- New stdlib: `Math.checked_div`, `Math.checked_mod`
- Tests: ~12 new tests in `no_panic` suite

**Estimated scope:** ~317 lines. No TIR/JIT/runtime changes.

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
