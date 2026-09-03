`[P3]` - [ ] **Unify `cap no_alloc` with the `@[no_alloc]` contract.**

Filed 2026-09-03, when the contract landed
(`specs/progress/2026-09-03-allocation-contracts.md`).

March now has two allocation checks with different answers:

- `cap no_alloc` (`lib/refinecheck/no_alloc.ml`) is syntactic and
  pre-optimisation. It walks the AST of every function in a `cap no_alloc`
  module and rejects tuple, record, boxed-constructor and lambda expressions.
  It runs in every mode, the interpreter included.
- `@[no_alloc]` (`lib/tir/alloc_contract.ml`) is a per-function contract
  checked on the final TIR, after Perceus and escape analysis, and is
  transitive over callees. It has no answer at all under the interpreter or
  `--check`, which never lower to TIR.

So the cap rejects code the contract accepts (a constructor Perceus reuses in
place) and accepts code the contract rejects (a call into an allocating
callee). Both behaviours are defensible in isolation; having both under two
spellings is not.

The blocker is the interpreter: `cap no_alloc` is the only allocation check
available where no TIR exists, and dropping it would leave `forge run` with
nothing. Deciding this needs an answer to "what should an allocation
guarantee mean under the interpreter" — plausibly a third verdict
("unchecked in this mode") rather than either of today's two.

When it is resolved, `specs/lang/capabilities.md` and its `docs/` copy each
carry a paragraph describing the split that should collapse into one
description.
