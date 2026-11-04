`[P2]` Diagnostics: put a type error's caret on the wrong subterm, not the enclosing call/literal.
Push expected types into lambda bodies (via the callee's callback signature), constructor arguments, and
list/tuple/record elements, recording a blame path the renderer turns into one sentence. Evidence and target
output: specs/plans/2026-11-02-diagnostics-depth-plan.md §X1. Acceptance: caret no wider than the wrong subterm; `scripts/types-oracle.sh` inference tier unchanged.

2026-11-03: first slice landed (constructors, list/tuple/record literals, path notes):
`specs/progress/2026-11-03-diag-x1-blame-literals-and-ctors.md` (diagnostics only; typing untouched). Open: lambda bodies inside calls,
`if`/`cond` branches against a known type, and the swapped pair on `x ++ "no"`.

2026-11-04: second slice landed (lambda bodies inside calls):
`specs/progress/2026-11-04-diag-x1-lambda-bodies.md`. Open: `if`/`cond` branches against a known
type, and the swapped pair on `x ++ "no"`.
