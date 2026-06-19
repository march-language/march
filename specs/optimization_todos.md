# Optimization & Feature Todos

Ranked by benefit-to-lift ratio. Each item links to its authoritative spec for full detail.

**Last updated:** 2026-06-18 (after Phase 3c `opts no_panic` landed)

---

## Tier 1 — High value, low lift

Do these first. Each is well-specified, bounded, and immediately useful to users.

---

### 1. Capability body enforcement — Phase 1: stdlib `needs` annotations

**Lift:** 0.5–1 day  
**Benefit:** Prerequisite for Phase 2; no user breakage  
**Spec:** `specs/capability-body-enforcement.md`

Add `needs IO.FileRead`, `needs IO.FileWrite`, `needs IO.Console`, `needs IO.Clock`,
`needs IO.Process`, `needs IO.Random` to the ~8 stdlib IO modules (`io.march`,
`file.march`, `system.march`, `csv.march`, `uuid.march`, `random.march`, `crypto.march`).
Pure annotation pass — no user code breaks, no type-checker change.

**Files:** ~8 stdlib `.march` files, 1–2 lines each  
**Tests:** Existing stdlib test suites must still pass; no new tests needed for Phase 1 itself

---

### 2. Capability body enforcement — Phase 2: body-scanning pass

**Lift:** 1.5 days  
**Benefit:** Catches missing capability declarations at compile time; ships as warning first  
**Spec:** `specs/capability-body-enforcement.md`  
**Prerequisite:** Phase 1 done

Extend `check_module_needs` to walk `fc_body` of all function clauses (and `DLet` RHS)
for calls to builtins in a `builtin_cap_table` (~50-entry map of builtin name → required
cap). Calls without a matching `needs` declaration emit a warning (initially) then an error.
Add `IO.Random` and `IO.Database` to `io_cap_hierarchy`.

**Key files:**
- `lib/typecheck/typecheck.ml` — extend `check_module_needs`, add `builtin_cap_table`
  (~25 lines for the walker, ~35 lines for the table)

**Tests:** ~15 new tests in `capability_body` group  
**Migration:** Warning-first; existing user code gets a grace period

---

### 3. Record field auto-satisfy (Feature 2)

**Lift:** 0.5–1 day (~30 lines)  
**Benefit:** Eliminates boilerplate `impl` blocks for accessor-shaped interfaces; zero runtime cost  
**Spec:** `specs/structural-interface-satisfaction.md §Feature 2`

When discharging `CInterface(Iface, TRecord[...])`, auto-satisfy single-method
accessor-shaped interfaces when the anonymous record has a field with matching name and
type. Does not apply to multi-method interfaces, named type aliases (`TCon`), or
non-accessor methods (binary, etc.).

**Example:**
```march
interface Named(a) do
  fn name(a) -> String
end

fn greet(x : { name: String, age: Int }) do
  "Hello " ++ x.name  -- auto-satisfies Named without an impl block
end
```

**Key files:**
- `lib/typecheck/typecheck.ml` — `discharge_constraints` CInterface arm, ~30 lines

**Tests:** 9 new tests in `record_auto_satisfy` group

---

## Tier 2 — Good value, medium lift

Worth doing in this order after Tier 1. Each has a clear payoff but requires more
implementation work.

---

### 4. P10 Phase 3 — NativeArray-backed DataFrame columns

**Lift:** Medium (stdlib rewrite, ~200 lines)  
**Benefit:** 5–10× for analytical workloads; NativeArray compiled path is already done  
**Spec:** `specs/optimizations.md §P10` (Phase 3 section)  
**Prerequisite:** P10 Phase 2 done ✅

Rewrite the hot paths in `stdlib/dataframe.march` to use `NativeArray` columns instead
of `List`-backed `IntCol`/`FloatCol`. The `Column` ADT already exists; this is wiring
the existing NativeArray builtins into the column storage layer.

Combined with stream fusion (already implemented) and columnar layout (already at
interpreter level), this makes March DataFrame queries competitive with pandas for
numeric workloads.

**Key files:**
- `stdlib/dataframe.march` — swap `IntCol(List(Int))` → `IntCol(NativeArray(Int))` etc.,
  update `filter_col_by_mask` and aggregation paths
- `stdlib/native_array.march` — already exists, no changes needed

**Tests:** All 75 existing DataFrame tests must pass; benchmark `bench/array_numeric.march`

---

### 5. `satisfy` declaration (Feature 1)

**Lift:** 1.5–2 days  
**Benefit:** Eliminates boilerplate `impl` delegation for newtype/accessor patterns  
**Spec:** `specs/structural-interface-satisfaction.md §Feature 1`

New `satisfy Iface for T` keyword that generates an `impl` block from matching functions
already in scope. Desugar-time expansion — no type-checker change beyond what Feature 2
already adds.

```march
fn name(u : User) -> String do u.name end

satisfy Named for User   -- generates impl Named(User) do fn name(u) do u.name end end
```

**Key files:**
- `lib/lexer/lexer.mll` — `SATISFY` token
- `lib/parser/parser.mly` — `satisfy_decl` production
- `lib/ast/ast.ml` — `DSatisfy of name list * name list * span`
- `lib/desugar/desugar.ml` — `expand_satisfy` function (~60 lines)
- Passthrough in eval, lower, format, LSP, coverage

**Tests:** ~11 new tests

---

### 6. P5 — Stdlib polymorphic specialization

**Lift:** Medium (no spec yet; requires design)  
**Benefit:** Smaller binaries + faster compile times; low user-visible runtime impact  
**Spec:** `specs/optimizations.md §P5`

Monomorphization already specializes user code. Some stdlib functions (`List.sort_by`,
`Map.lookup`, etc.) are instantiated at many different types, generating multiple copies.
Specialization with sharing would deduplicate identical-layout mono copies and reduce
binary size for programs that use the same type via many call paths.

This is a compile-time quality-of-life optimization rather than a runtime speedup.
Defer until binary bloat is a measured complaint.

---

### 7. P4 — Lambda lifting

**Lift:** Medium (no spec yet)  
**Benefit:** Low-Medium; Perceus + Escape already handle most target cases  
**Spec:** `specs/optimizations.md §P4`

Convert closures with ≤ 2 free variables to top-level functions by making free vars
explicit parameters. Avoids the struct allocation that Defun currently inserts when
Escape analysis can't stack-promote. Already marked "deferred" in the spec because the
existing Perceus + borrow + escape stack handles most real-world closure patterns.

Not worth prioritizing until profiling shows closure struct allocation as a hot path.

---

## Tier 3 — Very high value, very high lift (post-v1)

These are transformative but require research, multi-month timelines, or architectural
changes that are premature before v1 stabilizes.

---

### 8. P6 — Representation polymorphism / unboxed ADT fields

**Lift:** Very high (TIR type system + LLVM emit rewrite; research-grade)  
**Benefit:** Very high — zero-cost newtypes, unboxed numeric wrappers  
**Spec:** `specs/optimizations.md §P6`

Single-field constructors like `type Meters = Meters(Float)` currently heap-allocate
a struct. True unboxing would represent the constructor's payload as flat machine values
in registers, eliminating the heap struct entirely.

Requires extending TIR's type algebra with an unboxed variant kind, threading unboxedness
through mono/defun/perceus/llvm_emit, and handling the transition between boxed and
unboxed representations at ABI boundaries. No spec yet.

Gate on: measured evidence that wrapping types are a hot-path in real programs.

---

### 9. Hot code reloading

**Lift:** Very high (6 phases, months of work)  
**Benefit:** Transformative for production — zero-downtime deploys of Bastion apps  
**Spec:** `specs/hot-code-reload.md`

Erlang-style live code swapping. Phase 0 is a mandatory spike (prove native code can be
swapped without memory corruption). Model A (interpreter trampoline) is shippable after
Phases 0–2. Model B (native ORC JIT) is gated on the spike result.

Architectural tension: March's whole-program optimization (mono, defun, Perceus, LTO) is
in direct conflict with module isolation. The boundary must forfeit those optimizations.

Gate on: at least one production Bastion deployment that needs it.

---

### 10. Query-based / demand-driven compiler architecture

**Lift:** Very high (multi-month refactor of the entire pipeline)  
**Benefit:** Enables fine-grained incremental recompilation; critical for IDE speed at scale  
**Spec:** none yet

Replace the current linear pipeline (parse → desugar → typecheck → TIR → LLVM) with a
query-based architecture (like `rustc`'s `salsa`). Each compiler artifact becomes a
cached query invalidated by its inputs.

Premature before v1 — the pipeline is still evolving. Revisit when compilation latency
becomes the dominant user complaint.

---

## Summary table

| # | Item | Lift | Benefit | Spec? |
|---|------|------|---------|-------|
| 1 | Cap enforcement Phase 1 (stdlib annotations) | 0.5–1 day | Unlocks Phase 2 | ✅ complete |
| 2 | Cap enforcement Phase 2 (body-scanning pass) | 1.5 days | Catches bugs at compile time | ✅ complete |
| 3 | Record field auto-satisfy | 0.5–1 day | Kills impl boilerplate | ✅ complete |
| 4 | P10 Phase 3 (NativeArray DataFrame) | Medium | 5–10× analytical perf | ✅ partial |
| 5 | `satisfy` keyword | 1.5–2 days | Ergonomics win | ✅ complete |
| 6 | P5 stdlib specialization | Medium | Binary size / compile time | Outline only |
| 7 | P4 lambda lifting | Medium | Low; already largely covered | Outline only |
| 8 | P6 representation polymorphism | Very high | Zero-cost newtypes | Research |
| 9 | Hot code reloading | Very high | Zero-downtime deploys | ✅ complete |
| 10 | Query-based compiler | Very high | Incremental compilation | None |
