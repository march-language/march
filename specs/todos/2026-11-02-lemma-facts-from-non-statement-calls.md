`[P3]` A lemma call gives its fact only in statement position: `l(..)` on its own line, or
`let _ = l(..)`. A call written anywhere else (an argument, an `if` condition, a tail inside an
expression) is accepted, erased like any other, and contributes nothing to the proof
(`lemma_call_facts` in `lib/refinecheck/refine_check.ml`; plan ruling 4 of
`specs/plans/2026-11-02-reflection-phase2-lemmas-plan.md`). This is never unsound; it only skips
proofs written in another shape.

Done when a lemma call in an expression position contributes its fact to the obligations
that follow it in evaluation order, with the same rules (admitted, preconditions proved,
scope stays inside the branch), and a `reflect-lemma` test pins each new position.
