`[P3]` Ghost code: proof-only parameters, lets and functions, erased before codegen. **Done 2026-11-08.**

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

## What landed (2026-11-08)

- **Syntax.** `ghost` is a soft keyword (`lib/parser/token_filter.ml`), promoted
  only before `let`, `fn`/`pfn` or a parameter name: `ghost s : T` (AST
  linearity `Ghost`), `ghost let` (`bind_lin = Ghost`), `ghost fn` (attribute
  `"ghost"`, printed back as the keyword by `--fmt`). `ghost` stays a name
  elsewhere. Tree-sitter grammar extended.
- **Noninterference check** (`lib/desugar/ghost.ml`, run at the end of
  `Typecheck.check_module_core`). Ghost values reach only ghost positions:
  refinements, ghost lets, ghost arguments, lemma arguments, proof hints,
  ghost function bodies. Returning, branching, matching, capturing in a
  closure, passing to a runtime parameter, calling a `ghost fn` from runtime
  code: `ghost_in_runtime`. Observing a linear/affine value, a function with
  ghost parameters used as a value, ghost parameters on impl methods or on a
  function the desugarer merges (several clauses, a pattern parameter, a
  guard), and an unresolvable ghost name: `ghost_misuse`. A `ghost fn` is
  asserted reflected (`invalid_reflect` names it "ghost function"), which makes
  it pure, total and terminating. Tail-recursion warnings skip it.
- **Erasure** (`Ghost.erase`, after `Lemma_erase` in `bin/main.ml`): drops ghost
  parameters and the matching arguments, ghost lets, ghost functions, lemma
  calls (they run nothing) and lemma declarations left unreferenced; in a file
  with ghost code, a `()` statement an erased lemma call left. Syntax only, no
  verdict or solver. Resolution without the typechecker: a bare call is ghost
  in the file that declares it unless a local shadows it, and the name must
  not be another declaration of that file, a global (top level, prelude,
  builtin) or a `use` import; a qualified call (also through `alias`) is ghost
  only when a program module of that name declares it, so `List.member` never
  matches a user's ghost `member`. A rule the check could not see (a seeded
  check has no stdlib declarations) stops the build at erasure rather than
  leave a ghost argument behind.
- **Checker.** A match arm whose scope holds a hypothesis about a `ghost fn`
  gets the lemma body's pattern links (§4.3), so a ghost invariant on a matched
  parameter unfolds at the constructor (`refine_check.ml`, gated: a module with
  no ghost function sends the solver what it did before).
- **Worked proof**: `test/refine/ghost/bst.march`, a search tree whose order is
  stated with ghost bounds (`ghost fn bst(t, lo, hi)`), two lemmas, a lookup
  whose recursive calls each prove the subtree is ordered between narrowed
  ghost bounds, callers passing ghost arguments (one from a closure) and a
  `ghost let`; 10 obligations, all proved.
- **Erasure evidence**: `bst_erased.march`, the same lines with the ghost code
  blanked, emits identical LLVM IR and identical JavaScript (up to the file
  name), so signatures, closure captures and RC insertion match. The
  comparison failed before erasure was wired into the compile path and before
  erased lemma calls' `()` statements were dropped.
- **Tests**: `test/test_refine_ghost.ml` (group `ghost`, 25 cases: the worked
  example, both erasure comparisons, 15 rejects, accepted edge cases, the
  formatter); `test/errors/ghost_in_runtime_1`, `ghost_misuse_1`; explain pages
  `specs/lang/errors/ghost_{in_runtime,misuse}.md`; guide section "Ghost code"
  in `specs/lang/lemmas.md`.

The tree-to-set abstraction the milestone named is not the worked example:
a set-valued measure that uses `empty` is refused by reflection's R7, and a
`Bool` result contract does not use its body's facts yet. Both, the
remaining unsupported forms and actor ghost state are in
`specs/todos/2026-11-08-ghost-code-followups.md`.
