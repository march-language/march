# A caller's `len(xs)` fact does not reach a callee's `len`-bearing precondition

**Filed:** 2026-08-02 — surfaced while building `forge refine`
(`specs/progress/2026-08-02-forge-refine-precondition-suggestion.md`).

## Repro

```march
mod T do
  fn at(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do i end
  fn pick(xs : List(Int), i : Int) : Int do at(xs, i) end
end
```

`march --check --refine-report` reports the `at(xs, i)` call as
`skipped (solver-undecided)`, as expected — `i` carries no contract.

The problem is the next step. Write the *ideal* contract on `pick` by hand:

```march
fn pick(xs : List(Int), i : {Int | _ >= 0 && _ < len(xs)}) : Int do at(xs, i) end
```

and the obligation is **still** `solver-undecided`. The caller's assumption and the
callee's goal are the same predicate over the same two names, and it does not discharge.

## Why it matters beyond this one shape

Index-passing is the canonical reason to have a `len`-bearing refinement at all: a
bounds contract that cannot be forwarded one call deep only works on leaf functions.
It also means `forge refine` correctly reports `no-candidate` here — the tool never
proposes a contract the checker would not actually verify — so the gap shows up to users
as "the tool has no suggestion" rather than as a checker message.

## Where to look

`lib/refinecheck/refine_check.ml` — the precondition path (`note` / the call-site VC
builder) and `resolve_measure` / `resolve_measure_app`. The likely cause is that the
caller's `len(xs)` and the callee's `len(xs)` reflect to *different* SMT symbols, since
the callee's is resolved against the callee's parameter names and the caller's against
the caller's — the two are only the same fact if the argument at the list position is
syntactically the same variable, which is exactly the substitution that has to be made
explicit.

## Acceptance

- The hand-written `pick` above proves (`--refine-report` shows a proved precondition).
- A REJECT witness: `fn bad(xs, i : {Int | _ >= 0}) do at(xs, i) end` must still NOT
  prove — otherwise the fix would be laundering the goal rather than propagating a fact.
- `forge refine pick` then proposes `{Int | _ >= 0 && _ < len(xs)}`, which the existing
  candidate grammar already contains.
