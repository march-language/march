`[P2]` Diagnostics: put a type error's caret on the wrong subterm, not the enclosing call/literal.
Push expected types into lambda bodies (via the callee's callback signature), constructor arguments, and
list/tuple/record elements, recording a blame path the renderer turns into one sentence. Evidence and target
output: specs/plans/2026-11-02-diagnostics-depth-plan.md §X1. Acceptance: caret no wider than the wrong subterm; `scripts/types-oracle.sh` inference tier unchanged.
