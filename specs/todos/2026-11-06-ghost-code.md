`[P3]` Ghost code: proof-only parameters, lets and functions, erased before codegen.

Medium step 6 of `2026-11-06-verification-ladder-roadmap`. Dafny/Verus `ghost`.

## Why

Some proofs need state the program never computes: the abstract contents of a tree (the set
its nodes hold), a counter's history, the sequence of messages an actor has seen. Today that state
can only be expressed through measures over existing values. Ghost code lets a proof carry it
explicitly and have it erased.

## Wanted

- `ghost` parameters (`fn insert(t : Tree, x : Int, ghost s : Set(Int))`), `ghost let`, and
  `ghost fn` (reflected, never compiled).
- Typing rule: ghost values flow only into ghost positions, refinements and lemma arguments;
  using one in program code is a compile error. Erasure is the same pass that erases lemmas.

## Done when

- The rule is enforced (reject tests), erasure verified by the ir-oracle (a program with ghost
  code emits the same IR as without it).
- One worked proof that needs it, e.g. an insert into a binary search tree proved against a ghost
  set (a stepping stone for `2026-11-06-prove-map-set-contracts`).

## Erasure and ownership obligations (2026-11-07)

[F*, POPL 2016](https://fstar-lang.org/papers/mumon/paper.pdf) separates pure terminating proof
computation from effects and divergence. [Flux, PLDI 2023](https://nilehmann.github.io/papers/pldi23-flux.pdf)
uses ownership guarantees to reason about mutable locations. For March:

- Enforce noninterference transitively: a runtime branch, allocation size, return value or
  capability operation cannot depend on a ghost value, including through a closure, callback,
  pattern match or generic instantiation. A proof-only precondition cannot justify a runtime
  action unless established by the verification discipline at that boundary.
- Ghost code is pure and terminating. It cannot consume or duplicate a runtime linear resource,
  hold an RC reference that changes runtime uniqueness, or gain an IO capability. Specify ghost
  observations of runtime values separately from ownership transfer; reject unsupported cases.
- Ghost histories describe a model. They do not prove that external events happened; any bridge
  to an actor/file runtime must name its conformance assumptions.
- Add rejection fixtures for indirect ghost-to-runtime flow, capture, linear duplication and
  diverging ghost functions. Erasure comparisons cover LLVM and every supported backend that
  accepts the feature, including closure layouts and RC insertion, not just a scalar example.

First milestone remains a tree-to-set abstraction; actor histories follow after the erasure and
ownership rules hold. Do not introduce general proof-dependent runtime types.
