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

**IR-level (Phase 3b, this section):** After monomorphization, a new DCE/audit pass walks the TIR body of every function specialized with a constraining policy tag and verifies (or enforces) that no policy-violating operations remain.

### Pass design

The pass runs after monomorphization (`lib/tir/mono.ml`) and before defunctionalization.

**Step 1 — Identify constrained specializations.** Walk all monomorphized functions. If a function's type includes `Tagged(_, P)` where `P` is a constraining policy (defined in the policy table), collect it with its policy set.

**Step 2 — Walk TIR bodies.** For each constrained specialization, walk the TIR body and flag:
- **`NoAlloc` policy:** any `EAlloc` or `EStackAlloc` node (`lib/tir/tir.ml` — these are the only two allocation constructors; there is no `EBox`, `EAllocTuple`, or `EAllocVariant`)
- **`NoIO` policy:** any `EApp` or `ECallPtr` call to a function whose name is in the `needs IO` declared set (tracked in `env.module_caps` during typecheck; needs to be propagated into TIR metadata or re-queried at this pass)
- **`NoPanic` policy:** any `EApp` to a known panicking builtin (division, `unwrap`, `assert`, `panic`); see §3 for the panic-surface set definition

**Step 3 — Report or prune.**
- **Audit mode (default, Phase 3b initial):** Report violations as errors. "Function `dsp_callback` is specialized to `Tagged(DSP, Realtime)` but contains an allocation at line N. Move this allocation outside the realtime callback."
- **DCE mode (optional, Phase 3b follow-up):** Prune statically dead allocation branches — e.g., if a `match` arm that allocates is only reachable when a policy is `WithAlloc`, and we're specializing to `NoAlloc`, eliminate that arm. This is conditional dead-code elimination driven by the policy value.

Audit mode ships first; DCE mode is the harder follow-up.

### Policy table

Defined in `lib/tir/policy_dce.ml` (new file):

```ocaml
type policy_constraint =
  | NoAlloc   (* prohibits EAlloc and EStackAlloc nodes *)
  | NoIO      (* prohibits EApp/ECallPtr to IO-needful functions *)
  | NoPanic   (* prohibits EApp to panicking builtins; see panic_surface set in §3 *)

(* Maps policy type names to their constraints *)
let policy_table : (string * policy_constraint list) list = [
  ("NoAlloc",    [NoAlloc]);
  ("Realtime",   [NoAlloc; NoIO; NoPanic]);  (* realtime = all three *)
  ("NoPanic",    [NoPanic]);
]
```

### Integration with Phase 2c narrowing rules

Phase 2c's realtime-exclusion check (Check 7 in `check_decl`, `lib/typecheck/typecheck.ml:~4679`) pattern-matches on `Tagged(_, Realtime)` parameters and rejects co-presence of `Cap(Alloc)`, `Cap(IO)`, or `Cap(Panic)` in the same signature. Note: this check is in `check_decl`, not in `cap_subsumes` — `cap_subsumes` is purely the `cap_ancestors` membership test. The DCE pass is additive — it catches violations that slip past the declaration-level check (e.g., allocation injected via inlining of a non-tagged helper after typechecking).

### Implementation notes

- New `lib/tir/policy_dce.ml` (~200 lines): policy table, TIR walker, violation reporter
- `lib/tir/lower.ml`: call the new pass after `mono` and before `defun`
- Violations are `Error` diagnostics with the same `MPCode`/`MPText`/`MPBreak` structure as other capability errors
- DCE mode (conditional branch elimination) is a separate follow-up; audit mode ships first

**Estimated scope:** ~300 lines (new `lib/tir/policy_dce.ml` + 20-line integration in `lib/tir/lower.ml`). No runtime changes.

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
