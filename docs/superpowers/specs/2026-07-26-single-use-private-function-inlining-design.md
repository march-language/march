# Single-Use Private-Function Inlining

**Date:** 2026-07-26
**Status:** Approved design
**Target:** First implementation PR

## Summary

Add a separately named TIR optimization pass that inlines a small,
syntactically impure top-level function when its only reference in the compiled
artifact is one direct call. The pass runs after the ordinary pure-function
inliner and before constant propagation, folding, simplification, fusion, and
dead-code elimination.

The first PR retains the existing 50-node inlining threshold. It changes only
the purity policy for functions that can be relocated exactly once. It does not
introduce a new IR, change language semantics, alter ownership analysis, or
relax hot-reload boundaries.

## Motivation and Measurements

The ordinary inliner in `lib/tir/inline.ml` admits functions only when
`Purity.is_pure` returns true, their body contains at most 50 TIR nodes, and
they are outside recursive candidate SCCs and hot-reload boundaries. This is a
sound policy for multi-site inlining because it avoids duplicating observable
operations.

Purity is unnecessarily restrictive when a function has exactly one reference
and that reference is a direct call. Replacing that call with the function body
relocates the operations instead of duplicating them. The existing alpha
renaming and ANF substitution machinery already preserves binding hygiene.

The merged SCC-aware inliner was measured across all 91 non-JS
`test/native/*.march` fixtures. For each fixture, the final post-optimization
TIR dump was paired with emitted LLVM:

- 2,029 March function definitions were emitted and matched back to TIR.
- 2,468 direct calls targeted those definitions.
- 979 definitions had one TIR caller and one emitted LLVM call.
- 730 of those also had an address/function-value reference and were excluded.
- Recursive SCCs, entry/export-like names, and address-taken functions were
  excluded conservatively.
- 247 safe one-direct-use occurrences remained, representing 214 distinct
  function bodies across 51 fixtures.
- 217 of the 247 bodies contained explicit RC operations.

The size curve was:

| Maximum body size | Occurrences | Distinct bodies | Share of residual direct calls |
| ---: | ---: | ---: | ---: |
| 25 | 122 | 103 | 4.9% |
| 50 | 174 | 152 | 7.1% |
| 75 | 198 | 174 | 8.0% |
| 100 | 210 | 183 | 8.5% |
| 150 | 221 | 193 | 9.0% |
| 200 | 232 | 202 | 9.4% |
| Unlimited | 247 | 214 | 10.0% |

Keeping the existing 50-node threshold captures 174 measured call/definition
pairs, or 70% of the safe opportunity, while isolating this PR to one policy
change. A larger threshold is a separate follow-up decision.

These are compiler-output measurements, not a runtime-speedup claim.

## Goals

1. Inline syntactically impure top-level functions with exactly one total
   reference when that reference is an arity-correct direct `EApp`.
2. Preserve expression order and every Perceus-inserted ownership/RC operation.
3. Preserve recursive functions, address-taken functions, externally reachable
   functions, and hot-reload boundaries.
4. Give the optimization its own pass name, tests, phase trace, and
   independently measurable LLVM effect.
5. Let the existing downstream DCE remove definitions made unreachable.

## Non-Goals

- Raising the 50-node threshold.
- Inlining a function with more than one reference.
- Inlining address-taken functions or capture-free closures.
- Adding source visibility to TIR.
- Changing `Purity.is_pure` or its treatment of transitive user calls.
- Changing Perceus, Borrow, the closure ABI, LLVM ownership conventions, or
  language semantics.
- Relaxing a hot-reload boundary.
- Claiming runtime speedup from reduced call counts alone.
- Pinning the entire native corpus to a fixed residual-call golden.

## Existing Pipeline and Reusable Behavior

`lib/tir/opt.ml` runs a fixed-point loop, currently ordered as:

1. join points
2. known call
3. ordinary inline
4. constant propagation
5. folding
6. simplification
7. structural fusion
8. DCE

The ordinary inliner already supplies:

- `Inline.node_count`
- SCC-based recursive-candidate rejection
- alpha-renaming
- arity-checked ANF parameter substitution
- expression rewriting through lets, local functions, cases, and sequences
- hot-reload configuration scoped by `Opt.run`

`Dce.run` already follows inlining in every optimizer iteration and removes
unreachable top-level definitions. The new pass must not duplicate that
deletion logic.

## Architecture

Create `lib/tir/single_use_inline.ml` with a public entry point equivalent to:

```ocaml
val run : changed:bool ref -> Tir.tir_module -> Tir.tir_module
```

Register it in `lib/tir/opt.ml` immediately after ordinary inlining:

```text
join-points
known-call
inline
single-use-inline
cprop
fold
simplify
fusion
dce
```

The pass runs while `Opt.run`'s existing hot-reload configuration lifetime is
active. It may reuse a small helper from `Inline` for reloadability rather than
introducing a second mutable configuration.

The pass has two phases:

1. Analyze the current post-ordinary-inline module and select candidates.
2. Rewrite the module with an environment containing only those candidates,
   reusing the ordinary inliner's expansion machinery.

Because the optimizer is a fixed-point loop, analysis is recomputed on every
iteration after changes made by ordinary inlining.

## Operational Meaning of “Private”

Source `pub` visibility is not represented on `Tir.fn_def`. Standalone native
DCE also does not preserve a definition merely because it was public in source.
This design therefore uses the compiler's operational artifact boundary.

A function is non-private and ineligible when it belongs to the entry/root set
that DCE must preserve:

- `main` or a module-qualified `*.main`
- any name in `tm_exports`
- any function registered in `tm_tests`
- test setup/setup-all entry points
- migration entry points
- all functions when the module has no explicit seed, matching DCE's fallback

The root calculation should be factored from `lib/tir/dce.ml` into a reusable
helper so DCE and single-use inlining cannot drift.

Collision-dispatch implementation targets are reachable through
`Dispatch_registry` rows rather than ordinary TIR function references. When
analysis encounters a dispatch sentinel, every registered implementation
target must receive a synthetic non-direct reference. Such a target is
address-taken for this optimization and is ineligible.

RPC stubs are already placed in `tm_exports`; migration functions are explicit
roots. Hot-reload boundaries add an independent exclusion described below.

## Reference Analysis

Build the set of top-level function names, then traverse every top-level
function body. For each occurrence that identifies a top-level function,
record:

- referenced function name
- owning top-level caller
- occurrence kind: direct-callee or non-direct
- direct-call edge for SCC analysis, when applicable
- argument count for direct calls

References include every atom position:

- `EApp` callee and arguments
- `ECallPtr` function atom and arguments
- `EAtom`
- tuple, record, update, allocation, stack allocation, reuse, and field atoms
- RC/free operations
- case scrutinees and all nested expression forms
- `ADefRef` when its `did_name` identifies a top-level function

The traversal must respect lexical binding. Parameters, `ELet` variables,
branch binders, and local `ELetRec` names shadow equal top-level names. Only a
free occurrence of a top-level name counts.

The analysis counts occurrences, not distinct callers. Two direct calls from
one caller are two references and are ineligible.

A sole occurrence is usable only when it is the callee position of `EApp`.
Any occurrence as a value, argument, allocation field, indirect-call target,
or other atom position makes the function address-taken and ineligible.

## Candidate Selection

A function is a single-use candidate only when all conditions hold:

1. `not (Purity.is_pure fn.fn_body)`
2. `Inline.node_count fn.fn_body <= 50`
3. exactly one total free top-level reference exists
4. the sole occurrence is a direct `EApp`
5. the call arity equals `List.length fn.fn_params`
6. the function is outside every recursive direct-call SCC, including a
   singleton self-edge
7. the function is not in DCE's root set
8. the function is not reloadable under the active hot-reload configuration
9. the function is not a synthetic collision-dispatch target

No `fn_kind` is categorically excluded. A lifted apply function naturally
fails eligibility while its pointer remains stored in a closure. If other
passes eliminate every non-direct use and leave one direct call, relocating it
is valid under the same contract as any other function.

Pure functions remain the responsibility of the ordinary inliner. This pass
does not become an alternative pure-inlining policy.

## Rewriting and Evaluation Order

The selected candidate environment is passed to the existing inliner
rewriter. For the sole `EApp`, expansion:

1. alpha-renames parameters and local binders
2. verifies arity
3. wraps the renamed body in parameter lets using the original argument atoms

TIR is in ANF, so direct-call arguments are atoms and contain no evaluation to
reorder. `List.fold_right2` produces parameter bindings in signature order.
Every effect inside the callee body remains in its original order:

- `ESeq`
- `EIncRC`, `EDecRC`, atomic RC, and `EFree`
- `EReuse`
- I/O and actor/task builtins
- indirect calls
- partial operations and traps

The pass does not recursively rewrite the newly inserted body during the same
occurrence replacement. The optimizer's next fixed-point iteration handles any
new opportunities.

If an unexpected arity mismatch reaches rewriting, the occurrence remains
unchanged, matching the ordinary inliner's guarded behavior. No partial
rewrite is permitted.

## Ownership and RC Correctness

Perceus runs before optimization and has already made ownership operations
explicit. TIR function calls do not carry an additional implicit RC transfer
that disappears with the LLVM call instruction.

Inlining therefore relocates:

- caller-side RC operations surrounding the original call
- callee-side RC operations in the original body
- parameter aliases introduced as atom-valued lets

It must not synthesize, remove, combine, or reorder an RC operation. Subsequent
DCE may remove only bindings according to its existing impurity-aware rules.

This is the central correctness invariant for the feature.

## Recursion, TCO, and Scheduling

The direct-call graph is computed over the current module and recursive SCCs
are excluded before rewriting. This covers self recursion and mutual recursion
regardless of candidate ordering.

Because recursive callees are excluded, the pass does not remove a recursive
function boundary or rewrite a recursive call into an expanding body. Existing
self- and mutual-TCO analysis remains unchanged.

LLVM reduction-check analysis sees the post-inline caller body. If relocation
adds non-leaf work to a caller, the emitter continues to classify that caller
from its resulting body and emits its function-entry reduction check. The
50-node limit bounds additional work between function boundaries. Existing
preemption and reduction-check tests remain required regression gates.

## Hot Reload

The callee is excluded whenever its owning module is reloadable under the
active `Hot_reload.config`. This matches the ordinary inliner's conservative
callee-based exclusion and preserves every boundary function as a real
versionable definition.

No attempt is made to distinguish boundary-to-boundary from non-boundary calls
for this pass. A reloadable callee is never eligible.

## Error Handling and Invariants

The pass is conservative:

- unknown reference shape: count it as non-direct
- shadowing ambiguity: treat the occurrence as local, not top-level
- arity mismatch: do not inline
- missing function definition: no candidate
- uncertain external reachability: add a non-direct reference or root it
- uncertain recursion: exclude the component

The optimizer must never fail compilation merely because a potential
single-use opportunity cannot be proven safe.

## Testing

### Focused TIR Tests

Add tests covering:

1. one impure direct use is inlined
2. two direct calls from one caller are not inlined
3. calls from two callers are not inlined
4. one direct call plus one value/address reference is not inlined
5. a shadowing local variable does not count as a top-level reference
6. self recursion is not inlined
7. mutual recursion is not inlined
8. a 50-node body is admitted and a 51-node body is rejected
9. arity mismatch is left unchanged
10. `main`, module-qualified main, exports, tests, setup, migration, and the
    no-seed fallback remain rooted
11. collision-dispatch targets receive synthetic non-direct references
12. a closure apply function remains excluded while address-taken
13. exact `ESeq` and RC-operation ordering is preserved after substitution

### Hot-Reload Tests

Extend `test/test_hot_reload.ml` to prove:

- a one-use impure reloadable callee remains a direct boundary function
- the same module without hot-reload configuration is eligible
- included and excluded module-prefix overrides retain current behavior

### Emitted LLVM Regression

Construct a small one-use impure function with an explicit ownership operation
and a named direct caller. After `Opt.run` and LLVM emission, assert:

- no named call to the function remains
- no definition of the function remains after DCE
- the expected RC/runtime operations remain in the caller
- their textual order matches the original TIR order

LLVM's own optimizer must not participate in this test; it inspects March's
raw emitted LLVM.

### Native Semantic Regression

Add a compiled native fixture whose one-use helper combines:

- observable side effects in a fixed order
- an RC-managed value that remains live across the helper body
- a returned value consumed by the caller

Compare compiled output with the expected result. Run the fixture under the
project's sanitizer gates where supported.

### Existing Gates

Required verification includes:

- focused inliner group
- hot-reload suite
- self- and mutual-TCO suites
- reduction/preemption suites
- TIR evaluation/property tests
- full codegen suite
- native LLVM verifier corpus
- sanitizer gate
- documentation lint

## Measurement and Success Criteria

Rerun the 91-fixture measurement after implementation using the same method:

1. emit final phase dumps and raw LLVM for each non-JS native fixture
2. match TIR definitions to LLVM definitions
3. count residual direct calls to March-defined functions
4. count named definitions removed
5. report body-size and RC distributions

Baseline:

- 2,468 residual direct calls
- 247 safe unlimited one-use occurrences
- 174 safe occurrences at 50 nodes
- 51 fixtures containing at least one size-eligible opportunity

The implementation succeeds when:

- focused tests prove every safety exclusion and the positive case
- a named call and definition disappear in raw emitted LLVM
- semantic, ownership, hot-reload, TCO, preemption, verifier, and sanitizer
  gates remain green
- the corpus measurement shows a material reduction attributable to this pass

The measured reduction is reported rather than enforced as a fixed golden,
because fixture additions and unrelated optimizer improvements legitimately
change corpus totals.

## Follow-Up Decisions

After the first PR lands, use the same corpus method to consider a separate
threshold increase. The pre-change curve suggests 100 nodes as the next useful
point: it would expand the static opportunity from 174 to 210 occurrences,
while 150 nodes adds only 11 more beyond 100.

Capture-free closure allocation elimination remains a separate optimization.
This pass only makes an apply function eligible when all function-value uses
have already disappeared.
