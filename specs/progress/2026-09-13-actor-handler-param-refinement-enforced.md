# Actor handler parameter refinements are enforced (plan phase 3)

Landed 2026-09-13. Phase 3 of
`specs/plans/2026-09-13-refinement-enforcement-holes-plan.md`; closes the
handler half of
`specs/todos/2026-09-03-actor-state-and-handler-refinement-unchecked.md`
(the state-field half is phase 4 and that todo stays open for it).

## Mechanism

The typechecker registers each `on Msg(...)` as an ordinary constructor, so
the construction `Msg(x)` is the one point every route to the handler passes
through — `send`, `Actor.call`, a generated session endpoint, or a message
bound to a `let` first. `Refine_scope.collect_handler_sigs` builds a
message-name → `fn_sig` table (via `local_fn_def` + `sig_of_fn`, the same
synthesis a block-level `fn` uses); `Refine_check.visit`'s `ECon` arm files
the obligation through the unchanged `check_call`; `visit_decl`'s `DActor`
arm admits the handler's parameter refinements to its body exactly when the
message is in that table.

**Fail closed on a bare-name clash.** Message constructors are registered by
bare name program-wide, last one wins. A name defined by two handlers, or
shared with a `type` variant constructor, is withdrawn from the table: no
construction is obliged AND no handler body assumes. Obligation and
assumption read the same table, so they cannot disagree.

**Stated trust boundary (plan decision (b)).** A message that arrives from a
remote node was constructed by code this compiler did not check. The handler
body's assumption is documented as that boundary in
`specs/lang/refinement-types.md` / `docs/refinement-types.md`, not withheld.

## Tests

`test/test_refinecheck.ml`, group `actor-handler-contract`: violating send
rejected at the construction, a `let`-bound message checked where built, the
body discharging `need(n)` from the assumed `n > 0`, and the clash case
pinned from both sides (no obligation, no assumption). The phase 0 case for
this position still rejects — now because the construction violates.
`--refine-audit` reports the position Enforced; the `actor` hole fixture stays
for its state-field line and its baseline is regenerated.
