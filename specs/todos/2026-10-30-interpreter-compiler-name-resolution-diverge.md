`[P1]` The interpreter and the compiled build resolve some names differently, so one program prints
two different answers.

Found by the second soundness review of reflection phase 1a (2026-10-30); it predates reflection
(reproduces with `MARCH_REFLECT=0`, and with no refinement at all). Probes, in the review's scratch
area `review1a2/`:

- `use1/m.march`, `use1/m2.march`, `use2/m.march`: a module-local `fn g` and a `use A.*` that also
  supplies `g`, in either order. Which `g` a call means depends on the backend (and in `use2` the two
  `g`s have different types).
- `slist2.march`: an entry module with a nested `mod List do fn sum_int(xs) = 42 end` and a call
  `List.sum_int([1, 2])`: interpreted `42`, compiled `3` (the stdlib's).
- `al1/m2.march`: `alias A as B` placed before `mod B do fn g(n) = n + 50 end`, then `B.g(1)`:
  interpreted `51`, compiled `2`.

What is needed: one resolution rule (local, enclosing modules innermost first, `use`, `alias`) shared
by the typechecker, the interpreter and lowering, or an `ambiguous_name` error where two of them can
supply a name. Until then the refinement checker treats every such site as unresolved and never
unfolds it (`Refine_term.graph.ambiguous`, `specs/progress/2026-10-30-reflection-phase1a.md`).
