# `@[no_alloc(transient)]` — the transient allocation contract

**Landed:** 2026-09-03. Extends the contract from
`specs/progress/2026-09-03-allocation-contracts.md`; design context in
`specs/2026-09-03-allocation-contracts-design.md`.

## The property

`@[no_alloc]` states "this function does not allocate". A frame loop, a request
handler or a tick does allocate — a dozen cells per frame — and frees all of
them again before it returns, a net live-object delta of zero. That is the
property such code actually has, and the bare form cannot state it.

`@[no_alloc(transient)]` states it: **nothing this function allocates survives
the call.**

## The check

`lib/tir/alloc_contract.ml`, `retaining_fns`, on the same final TIR the bare
contract sees. Two fixpoints over the call graph, both about where a value ENDS
UP rather than whether one was made:

1. `returns_fresh f` — may `f`'s returned value BE a fresh allocation?
   Whatever a function returns outlives the call by definition. An
   `EReuse`/`EAllocHole (Some _)` result does not count (that cell came in
   through a parameter, so returning it hands back the caller's own object),
   nor does an `EStackAlloc` (escape analysis only produces one for a value it
   proved does not leave the frame).
2. `leaks f` — does `f` hand a value to something with its own lifetime? An
   `ESetField` write into an object it did not allocate, a message to an actor
   mailbox, a `Vault` write, a spawned task's closure, an `extern`, or a call
   through an unknown closure. `named_builtin_retains` is TOTAL over
   `Builtin_name.t`, so adding a builtin without classifying it fails to
   compile the compiler — the same discipline `named_builtin_allocates` uses.

`f` is transient iff neither holds for `f` and neither holds for anything `f`
calls. A callee that RETURNS a fresh value does not propagate: dropping that
value is exactly what the form allows, and is the case the bare form rejects.

## What it deliberately does not cover

An amortized growth path — a buffer that reallocates its storage and keeps the
new storage — is *retained*: the new storage reaches a value the function
returns. `transient` rejects it, and the docs say so, so nobody expects the
form to bless growable buffers.

Blind spot, shared with the bare contract: a value that is neither released nor
reachable — a leak — is not "retained" by this analysis, because nothing in the
final TIR says where it went. The form pins "does not retain", not "does not
leak"; `march_live_allocs` is the instrument for the latter.

## Surface, tooling, diagnostics

- `@[no_alloc(transient)]` on `fn`/`pfn`. `transient` is a KEYWORD (a
  supervisor restart type), so `fn_attr` spells this payload out rather than
  un-reserving it; the typo guard lists all four forms.
- Diagnostic: ``` `f` is marked @[no_alloc(transient)] but retains an
  allocation. In `f`: it returns a freshly allocated `Box`. ``` Never
  downgraded by `--no-opt`: the verdict is about where values end up, and
  skipping the optimiser cannot turn a retained value into a released one.
- LSP: the diagnostic at the function's name span, and `✓ no_alloc(transient)`
  as the lens when it holds (the lens names the form, so the two contracts are
  distinguishable at a glance).
- `generation_candidates` now returns `(decl_info * form)` and picks the
  STRONGEST form that holds — `@[no_alloc]` when the function allocates nothing
  at all, `@[no_alloc(transient)]` when it allocates but retains nothing. Both
  `--report-contracts` and the LSP quick fix use it, so `forge fix --contracts`
  inserts the right attribute with no change of its own.

## Verification

`test/test_alloc_contract.ml`, group `alloc_contract`: accept a dead
allocation; accept a callee's dropped result (asserted against the SAME source
under both forms, so it is a contrast rather than two unrelated facts); reject
a returned allocation, an extern, and a transitive leak that names the callee;
the typo guard. `lsp/test`: the diagnostic span and the form-naming lens.
`forge/test`: `forge fix --contracts` still round-trips.

## Fixture note

Several existing fixtures used `Box(Int, Int)` as "a heap cell". That type is
now an unboxed aggregate (see the companion item), so those fixtures were moved
to `Box(Int, String)` — which keeps them measuring what they name.
