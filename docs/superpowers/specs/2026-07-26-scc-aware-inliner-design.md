# SCC-Aware Inliner Candidate Selection

## Goal

Reduce residual direct calls in emitted LLVM by allowing small, pure functions
in an acyclic caller/callee chain to remain inliner candidates at the same
time.

The change must not alter March semantics, TIR representation, ownership/RC
rules, hot-reload boundaries, or the mechanics of expression substitution.

## Current Behavior

`lib/tir/inline.ml` first selects functions that are:

- pure,
- at most `inline_size_threshold` TIR nodes,
- not directly self-recursive, and
- not hot-reload boundaries.

It then removes every candidate that calls any other candidate. This prevents
mutually recursive functions from expanding forever, but also rejects acyclic
callers.

The fixed-point optimizer can recover some acyclic chains over later
iterations. It cannot recover a caller whose callee is inlined first and makes
the caller exceed the size threshold. That caller remains as a residual LLVM
call even though it was small enough to inline before the callee expansion.

## Chosen Design

Replace the “calls another candidate” filter with cycle-aware filtering.

1. Build an initial pool using purity, size, and hot-reload checks; recursion is
   handled by the graph instead of the existing `calls_self` prefilter.
2. Build a direct-call graph over that initial pool.
3. Add an edge `f -> g` for each `EApp` to another pooled function.
4. Compute strongly connected components over that graph.
5. Remove:
   - any component containing more than one function; and
   - any singleton component with a self-edge.
6. Keep every function in the acyclic remainder in `fn_env`.
7. Run the existing `inline_expr` traversal unchanged.

Graph traversal follows the same expression coverage as the existing filter,
including `ELet`, `ELetRec`, `ECase`, and `ESeq`. `ECallPtr` does not create an
edge; `Known_call` remains responsible for converting statically known closure
calls before the inliner runs.

## Correctness Boundaries

- Purity and the 50-node threshold remain unchanged.
- Hot-reload boundary functions remain excluded before graph construction.
- Recursive SCCs are excluded as a unit, preventing fixed-point code growth.
- Alpha-renaming and ANF argument binding remain unchanged.
- Inlining still performs one substitution level per optimizer iteration.
- No new IR node, annotation, ownership rule, or RC transformation is added.
- Calls to functions outside the candidate set do not affect cycle detection.

## Alternatives Rejected

### Bottom-up topological inlining

Inlining callees into callers in graph order could reduce optimizer iterations,
but it changes when size is measured and makes code-growth policy part of this
PR. That is broader than necessary.

### Raising the fixed-point iteration limit

More iterations do not fix the body-growth case: once a caller grows beyond the
threshold, it remains ineligible. It also adds compile-time cost without a
structural bound.

## Tests

### Unit tests in `test/test_codegen.ml`

- An acyclic candidate caller remains eligible even when it calls another
  candidate.
- A self-recursive function is not inlined.
- Both members of a mutually recursive pair are not inlined.
- A hot-reload boundary call remains intact.

### Emitted-LLVM regression

Compile a fixture with:

- an outer pure wrapper initially below 50 nodes;
- a small pure callee used inside the wrapper;
- enough wrapper body nodes that inlining the callee pushes the wrapper above
  50 nodes; and
- `main` calling the outer wrapper.

Before the change, the emitted LLVM contains a direct call to the outer
wrapper. After the change:

- no call to the outer wrapper remains; and
- DCE removes its unused definition.

The assertion targets the named call/definition rather than total LLVM call
count, which would be noisy because runtime and allocation calls are expected.

### Regression suites

Run:

- the inliner unit-test group;
- hot-reload inliner tests;
- TIR tests;
- the two known monomorphization property seeds;
- the full codegen suite; and
- `git diff --check`.

## Measurement

The PR is successful when the deterministic fixture loses the named residual
LLVM call and definition.

Also report, without making them merge gates:

- total direct-call count in the fixture before and after;
- emitted LLVM byte size before and after; and
- compile time for repeated fixture compilation.

Runtime performance is explicitly not a success criterion for this PR.

## Non-Goals

- Single-use impure-function inlining.
- A larger inlining threshold or profile-guided threshold.
- Recursive-function partial inlining.
- Bottom-up/topological body rewriting.
- Capture-free closure allocation elimination.
- Changes to LLVM’s own inliner configuration.
