# Per-function transitive capability closure

**Status:** design, not yet implemented.
**Motivates:** closing the `needs` warning-vs-error gap
(`specs/todos/2026-08-03-undeclared-capability-is-only-a-warning.md`,
and item F1 of `specs/todos/2026-07-07-p2-compiler-capabilities-effects-found-during-core-march-widening.md`).

## The problem this exists to unblock

`check_module_needs` treats an undeclared capability two different ways:

| Check | Trigger | Severity |
|---|---|---|
| Check 1 | `Cap(X)` in a signature | **error** |
| Check 4 | transitive `use`/`import` of a module that needs `X` | **error** |
| Check 5 | `extern` declaring `Cap(X)` | **error** |
| **Check 1b** | a capability **builtin called directly in a body** | **warning**, exit 0 |
| **Check 1c** | an `extern` block implying `IO.Foreign` | **warning**, exit 0 |

So a module calling `file_write` directly, never threading `Cap(X)` through a
signature, compiles clean. The declared capability set is a hard floor for
capability-*passing* code and merely advisory for direct builtin calls —
which is what `docs/capabilities.md:181` now honestly documents.

**The naive fix does not work.** Flipping 1b/1c to errors forces `needs`
declarations onto the stdlib modules that genuinely do IO — measured
2026-08-06: 176 files across the corpus emit these warnings (23 stdlib, 39
bench, 114 test/native), dominated by `IO.Console` from `print`. That alone
would be mechanical. The problem is what happens next: Check 4 already
propagates a module's needs to its importers at **module granularity**, and
it is already an error. Verified:

```march
mod Consumer2 do
  import Helpers          -- Helpers declares `needs IO.Console`
  fn f(x : Int) : Int do pure_double(x) end   -- uses only the PURE function
end
```
→ `ERROR: module Consumer2 imports Helpers which requires Cap(IO.Console)`, exit 1.

So contracting `List` (whose `pmap` calls `task_spawn`) with `needs IO.Spawn`
would force `needs IO.Spawn` on every module that imports `List` to call
`map`. Same for `Prelude`/`IO.Console`, `Seq`/`IO.FileRead`,
`DateTime`/`IO.Clock`. Every March program would land at `needs IO`, and the
capability system's precision — its entire value — would evaporate.

**The blocker is granularity, not severity.** This document specifies the
granularity fix. Flipping the severity is a separate, later decision.

## What has to be built

```
caps(f) = own(f) ∪ ⋃ { caps(g) | g ∈ refs(f) }
```

to fixpoint: a function's capabilities are the ones it uses directly, plus
everything needed by every function it references.

`own(f)` already exists as `own_cap_closures`. `refs(f)` does not, and the
transitive union does not. There is **no per-function transitive capability
analysis anywhere in the codebase today**.

### Why neither existing table fits

- `cap_closures` = own ∪ `module_wide_caps`, where `module_wide_caps` is the
  module's declared `needs` **plus everything propagated module-granularly
  from its imports**. That is precisely the pollution this design removes.
- `own_cap_closures` = own signature/body/extern only, deliberately excluding
  module-wide (added for the `migrate_state` IO-free check). It has **no
  call-graph transitivity**.

Confirmed by construction, not assumption:

```march
pfn helper(p) do file_read(p) ... end
fn public_reader(p) do helper(p) end
```

`calls_in_expr` on `public_reader` yields `["helper"]`;
`List.assoc_opt "helper" builtin_cap_table` is `None`; so
`own_cap_closures["CapProbe.public_reader"] = []` while the helper holds
`IO.FileRead`. Module-level aggregation hides this — `march caps` correctly
reports `{"caps":["IO.FileRead"]}` — which is why it has never mattered.
Propagating `own_cap_closures` per-function would **under-report**: the
fail-open direction, silently reopening the hole this work exists to close.

### The circularity, and how it breaks

`cap_closures` is built from `module_wide_caps`, which contains
module-granularly propagated import caps. If per-function closures become the
source of truth for propagation *and* are derived from `cap_closures`, that is
a cycle.

Break it by computing over `own_cap_closures` ∪ reference edges, entirely
independent of `module_wide_caps`. `own_cap_closures` exists precisely because
someone already needed a module-wide-free projection, so the clean input is
already there.

### Edge basis is soundness-critical

`refs(f)` must be built from **`free_vars_expr`-style reference collection,
not `calls_in_expr`**.

- `calls_in_expr` collects only `EApp` with an `EVar`/`EField` callee.
- `free_vars_expr` collects every `EVar` reference, bare and dotted,
  respecting shadowing.

A function passed as a *value* — `map(xs, Helpers.noisy)` — is invisible to
the first and visible to the second. Building on calls-only is fail-open.
Both existing precise mechanisms already use the broader basis:
`dependency_order_dfn_run`'s `deps_of` uses `free_vars_expr`, and
`record_use` fires per `EVar`.

## Machinery that already exists

| Piece | Gives us |
|---|---|
| `module_refs_in_decls` + `unqualified_module_deps` + Kahn fallback (`typecheck.ml`) | Modules are **already topologically ordered** — a module's dependencies are checked before it. |
| `dependency_order_dfn_run` | An intra-run function call graph: `deps_of` → `free_vars_expr` → `local_of`, DFS post-order, explicitly SCC-tolerant. |
| `record_use` + `import_idx` | Per-`EVar` reference tracking **with import provenance** — the demand side of Step 3. |
| `cap_closures` / `own_cap_closures` | Per-function tables, shared `Hashtbl`, surviving env threading. |

Both halves have in-repo precedent. Nothing needs inventing from scratch.

## Plan

### Step 1 — Unify `calls_in_expr` (no behavior change)

There are **three** copies today:

- `typecheck.ml:7932` — serves the capability body-scan
- `typecheck.ml:9710` — **byte-identical**, shadows the first, serves `check_no_panic_module`
- `panic_surface_by_proof.ml:112` — structurally the same walk, returning
  `(name, name_span, app_span)` triples instead of `(name, span)` pairs

The duplication inside `typecheck.ml` is pre-existing: `4f85ac9b` added one
for `no_panic`, `1ee94685` the other for the caps body-scan.

A `KEEP IN SYNC` comment was added on the first copy in #199 — **on the wrong
one**: `panic_surface_by_proof.ml` mirrors the `no_panic` copy (`:9710`),
which carries no note. A maintainer adding an expression form to `:9710`
would never see the warning that drift there is fail-open.

Fix: one walker in `lib/ast/calls.ml`, returning the richer triple; consumers
project what they need. `march_ast` has zero dependencies and both
`march_typecheck` and `march_refinecheck` depend on it, and `lib/ast/` already
hosts a non-definition module (`span_remap.ml`), so this is consistent with
existing structure — and it resolves the dependency-direction problem that
forced the copy in the first place (`march_refinecheck` depends on
`march_typecheck`, not the reverse).

This converts a fail-open drift class into a structural impossibility rather
than relocating a comment about it.

**Verification:** diagnostics byte-identical across the corpus before/after.

### Step 2 — The closure (new analysis, no behavior change)

Compute `caps(f)` per the formula above, over `own_cap_closures` ∪ reference
edges, independent of `module_wide_caps`. Fixpoint with SCC handling; module
topological order means one pass covers the acyclic majority, cycles iterate.

Sets only grow and capabilities are finite, so termination is guaranteed.

**Verification, two parts — the second is the one that protects us:**

1. On a fixture where a public function reaches a capability only through a
   private helper, the closure contains it.
2. For every module, the union over its functions' transitive closures
   **equals** today's module-level aggregate. This proves the new analysis
   loses nothing the current one finds — an accept-only test could not tell a
   working closure from one that returns everything, or nothing.

### Step 3 — Demand-driven propagation (behavior change, strictly loosening)

Widen the import entry from `ie_used : bool ref` to also record which names
matched (`record_use` already computes this and throws it away), then have
Check 4 and `module_wide_caps`' propagated component consult the referenced
functions' closures instead of `env.module_caps`.

Shadowing is already handled: `UseAll`'s rebind set skips anything in
`env.local_fns`.

Note `import A` parses to `UseAll` (binds bare names) and `use A` to
`UseSingle` (references stay qualified, handled by the prefix index) — both
paths need covering.

This can only **reduce** what a module must declare, so it cannot introduce a
false positive and nothing that compiles today stops compiling.

**Verification:** stdlib sweep shows no new errors anywhere; a fixture
importing a module for its pure function no longer inherits the impure caps.

### Step 4 — Flip 1b/1c to errors (NOT scoped here)

Held as a separate decision. After Step 3, re-measure the blast radius — the
176-file figure is pre-Step-3 and should shrink substantially, to roughly "the
stdlib modules that genuinely do IO, plus whoever actually calls their impure
functions" — and decide with that number in hand.

## Constraints

- **Both failure directions matter.** A false positive (rejecting correct
  code) is this subsystem's cardinal sin; but a capability that promises
  something and does not deliver is equally serious. Steps 1–3 are all
  non-loosening or strictly-loosening, so neither direction is at risk until
  Step 4.
- **No second source of truth.** The closure must not become a parallel
  capability analysis that can drift from what `march caps`/`forge audit`
  report — Step 2's verification #2 pins this.
- **Do not widen any existing contract as a side effect.**
- Both doc copies (`docs/*.md`, `specs/lang/*.md`) for user-visible changes;
  `CHANGELOG.md`; a `specs/progress/` note per landed step.

## Open questions

- Cyclic module dependencies are *tolerated* by the existing topological sort
  rather than rejected. A single pass is not sufficient there; the fixpoint
  must iterate across modules, not only within one.
- Whether `record_fn_caps` covers every function form (`DFn`, actor handlers,
  `DLet` bodies, interface methods) densely enough that no reference edge
  points at a function with no `own(...)` entry.
