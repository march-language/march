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

Phase 2's `Handle(R, S)` and `Tagged(X, T)` rely on implicit type variable inference for state and policy parameters. This works — but library authors cannot express constraints directly in signatures:

```march
-- Today: S is implicit, constraint communicated only by which transition functions exist
fn with_conn(h : Handle(Conn, S), f : (Handle(Conn, Open)) -> (a, Handle(Conn, Open))) : (a, Handle(Conn, S))
```

A reader cannot tell from this signature what states `S` may take, whether `S = Open` is required, or what the allowed transitions are. Phase 3 adds explicit syntax:

```march
fn with_conn[S : ConnState](h : Handle(Conn, S), f : (Handle(Conn, Open)) -> (a, Handle(Conn, Open))) : (a, Handle(Conn, S))
```

Now `S : ConnState` tells the reader (and compiler) that `S` must be one of the variants of `ConnState`.

### Syntax

Type parameter bounds use `[TypeVar : BoundType, ...]` after the function name, before the value-parameter list:

```march
fn open[S : ConnState](h : Handle(Conn, S)) : Handle(Conn, Open)
fn close[S : ConnState](h : Handle(Conn, S)) : Handle(Conn, Closed)

fn process[P : AllocPolicy](cap : Tagged(Alloc, P), buf : Buffer(Byte)) : Buffer(Byte)
fn fft[N : TNat](cap : Tagged(SIMD, N), buf : Buffer(Float32, N)) : Buffer(Complex32, N)
```

Bounds appear only on `fn` and `pfn` declarations (not lambdas — lambdas use implicit inference as today).

### What a bound means

`[S : ConnState]` means: `S` must unify with one of the constructors of `ConnState`. At call sites:
- If `S` is inferred to a concrete constructor (`Open`, `Closed`), the compiler checks it is a constructor of `ConnState`. Error if not.
- If `S` remains polymorphic across the function body, the compiler tracks the bound and reports a violation if any operation on `S` is not valid for all constructors of `ConnState`.

The bound is **checked at use sites, not definition sites** — a bound is a constraint on the caller's instantiation, not a restriction on what the body can do. (This parallels OCaml/Haskell typeclass constraints.)

### Relationship to interfaces

`[S : ConnState]` where `ConnState` is an ADT bounds `S` to the constructors of that ADT. This is *not* an interface bound — it does not require `S` to implement any typeclass. It is purely a domain constraint for documentation and error messages.

If the bound is an interface name (`[a : Ord]`), it becomes a standard typeclass constraint — existing mechanism, same syntax. The bracket syntax unifies both cases.

### Implementation notes

- New parser rule: optional `[bound_params]` between function name and `(`:  
  `fn name [bound_params] (params) : ret do body end`
- `bound_params` = comma-separated `LOWER_IDENT COLON type_expr`
- AST: new `fn_bounds : (name * ty) list` field on `DFn` / `DPFn`
- Typecheck: during `infer_fn_def`, add bounds to the constraint environment before checking the body; at each call site unification, verify that inferred arguments satisfy their bounds
- Error messages: "type variable `S` was inferred to be `Foo`, which is not a constructor of `ConnState`"
- The `[...]` syntax only appears on named declarations; the parser must not confuse it with array or list syntax (which does not appear in declaration position)

**Estimated scope:** ~250 lines (`parser.mly`, `ast.ml`, `typecheck.ml`). No eval, TIR, codegen, or runtime changes.

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
- **`NoAlloc` policy:** any `EAlloc`, `EAllocTuple`, `EAllocVariant`, `EBox` node — allocation sites
- **`NoIO` policy:** any call to a function that `needs IO` in its declaration
- **`NoPanic` policy:** any `EPanic`, `EAssert`, integer division (`EBinOp Div`), array indexing without bounds result type

**Step 3 — Report or prune.**
- **Audit mode (default, Phase 3b initial):** Report violations as errors. "Function `dsp_callback` is specialized to `Tagged(DSP, Realtime)` but contains an allocation at line N. Move this allocation outside the realtime callback."
- **DCE mode (optional, Phase 3b follow-up):** Prune statically dead allocation branches — e.g., if a `match` arm that allocates is only reachable when a policy is `WithAlloc`, and we're specializing to `NoAlloc`, eliminate that arm. This is conditional dead-code elimination driven by the policy value.

Audit mode ships first; DCE mode is the harder follow-up.

### Policy table

Defined in `lib/tir/policy_dce.ml` (new file):

```ocaml
type policy_constraint =
  | NoAlloc   (* prohibits EAlloc, EBox, EAllocTuple, EAllocVariant *)
  | NoIO      (* prohibits calls to IO-needful functions *)
  | NoPanic   (* prohibits EPanic, EAssert, integer division, bounds-unguarded indexing *)

(* Maps policy type names to their constraints *)
let policy_table : (string * policy_constraint list) list = [
  ("NoAlloc",    [NoAlloc]);
  ("Realtime",   [NoAlloc; NoIO; NoPanic]);  (* realtime = all three *)
  ("NoPanic",    [NoPanic]);
]
```

### Integration with Phase 2c narrowing rules

Phase 2c's `Tagged(DSP, Realtime)` narrowing in `cap_subsumes` remains. The DCE pass is additive — it catches violations that slip past the declaration-level check (e.g., via inlining from a non-tagged helper that happens to allocate).

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

A module-level `opts` directive:

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

- New `opts` keyword (or reuse existing `opts` if present in lexer — check first)
- `opts no_panic` recorded as a flag in module AST / type environment
- New `panic_surface` metadata field in the builtin table (small addition to `typecheck.ml`)
- Transitive panic analysis: during `check_module`, for each fn in a `no_panic` module, verify no call in its body has `panic_surface = true`
- Error message: names the specific panic site and suggests the non-panicking alternative

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

A second root alongside `Cap(IO)`. The hierarchy would live in `io_cap_hierarchy` (rename: `cap_hierarchy`) in `typecheck.ml`.

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
