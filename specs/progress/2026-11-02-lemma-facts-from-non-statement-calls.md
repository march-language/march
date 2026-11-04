`[P3]` A lemma call gives its fact only in statement position: `l(..)` on its own line, or
`let _ = l(..)`. A call written anywhere else (an argument, an `if` condition, a tail inside an
expression) is accepted, erased like any other, and contributes nothing to the proof
(`lemma_call_facts` in `lib/refinecheck/refine_check.ml`; plan ruling 4 of
`specs/plans/2026-11-02-reflection-phase2-lemmas-plan.md`). This is never unsound; it only skips
proofs written in another shape.

Done when a lemma call in an expression position contributes its fact to the obligations
that follow it in evaluation order, with the same rules (admitted, preconditions proved,
scope stays inside the branch), and a `reflect-lemma` test pins each new position.

## Fixed (2026-11-04)

`Refine_check.inner_lemma_facts`: after a block statement, the facts of every lemma call the
statement always evaluates (a `let` right-hand side, a named `let u = l(..)`, a nested block's
statements, call arguments, tuple and constructor fields, an `if` condition, a `match`
scrutinee), by `lemma_call_facts`'s rules. Not under a branch, a lambda, or the right operand
of `&&`/`||`. A fact naming a name the statement binds is dropped. An `if` condition's calls
also reach both branches. A nested block's own statement-position call is warned once.

Still open: a lemma call inside a call's own arguments does not reach that call's
precondition, because a call's preconditions are checked before its arguments are walked
(documented in `specs/lang/lemmas.md`, "What lemmas don't do (yet)").

Tests: `reflect-lemma` `pos_proved` (named `let`, nested block, tuple element, `if`
condition; all skip before) and `pos_red` (no lemma, a branch, a lambda, a rebound name, `&&`).
