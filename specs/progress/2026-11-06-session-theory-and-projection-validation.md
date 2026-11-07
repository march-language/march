`[P2]` `Session.Theory` and translation validation of both projectors (lemmas C0, M5, C1, C2, M6)

Phase C of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§5.2, §5.3, §7), first
part.

## Before

Two OCaml projectors (`Typecheck_session.project_steps_at` for `Chan(Role, Proto)`,
`Desugar_endpoints.project` for `@[endpoints]`) implemented the same rules twice, and nothing
said what a protocol means or checked that they agreed. The guarantee report labelled a
protocol's projection `checked (compiler)`.

## Fix

- **C0.** Lemmas over a mutual datatype pair with an n-ary branch list (`SessionLocal`/`SessionLBranches`)
  prove, with a mutually recursive lemma pair as the induction; the binary-choice fallback is
  not needed.
- **M5: `stdlib/session_theory.march` (`Session.Theory`).** `SessionGlobal` (`GMsg`, `GChoice` over
  `SessionGBranches`, `GLoop(body, after)` with `GVar` de Bruijn back-edges, `GEnd`), `SessionLocal`
  (`LSend`/`LRecv` with peer, `LChoose`/`LOffer` over `SessionLBranches`, `LRec`, `LVar`), over `Int`
  ids. `project(g, r, multiparty)` with `merge` (multiparty only: identical branches merge,
  else an offer) and `loop_of` (a role not in a loop's body skips to `after`), exactly the two
  projectors' rules. `dual`, `erase` (peers to 0), `same`/`same_bs` (structural equality,
  written out), `informed` (every non-chooser whose branches differ receives the chooser's
  message first; two-party offers are told by the label), `binary`.
- **Laws, in `stdlib/lemmas.verified`:** C1 `dual_dual`(`_bs`); C2 `project_dual`(`_bs`):
  `!binary(g, a, b) || erase(project(g, b, false)) == dual(erase(project(g, a, false)))`, with
  `merge_binary`, `dual_loop_of`, `erase_loop_of`; and `same_eq`(`_bs`). C2 is stated over
  `erase`: a send's peer is the other role on each side, so a peer-keeping `dual` cannot match.
- **M6.** `March_ast.Session_term` mirrors the terms in OCaml, with `global_of_steps` (a
  choice's branches carry the steps after it, `stop` is `GEnd`; crash branches and `may crash`
  are refused as outside the fragment). Each projector converts its own output faithfully:
  `Typecheck_session.theory_view` (recorded per protocol at projection; a binary
  `SSend`/`SRecv` gets the other role as peer; payloads by the projector's own `surface_ty`) and
  `Desugar_endpoints.theory_view` (fused label + head message unfused; a message is its
  constructor and payload, because that projector merges only identical constructors).
  `bin/session_validate.ml` evaluates `Session.Theory.informed`, `project` and `same` in the
  interpreter (`Witness`) on those ground terms. `march --validate-projections FILE`: one line
  per protocol, projector and role; exit 1 on a disagreement (a compiler bug).
- **Report.** `--guarantees` labels an agreeing projection
  `proved (spec) · validated (compiler)` (new label, between `checked (compiler)` and
  `proved`), with `project_dual` named for two roles; a role outside the fragment is
  `not checked` with the reason; a disagreement is `violated`. Multiparty protocols keep
  `pairwise duality: checked (compiler)` (the existence check) until C3.

## Evidence

- Every protocol in the repo's `.march` files (217 files with a protocol under test/,
  examples/, stdlib/, docs/): 972 projections agree, 0 differ, 44 outside the fragment (a role
  that may crash), 4 where `@[endpoints]` does not apply.
- RED on purpose: converting the typechecker's multiparty sends as receives makes 7 rows of
  the test protocols `DIFFERS` and the run exit 1.
- Found: `@[endpoints]` does not merge a bystander's branches that differ only in synthesised
  constructor names (todo `2026-11-06-endpoints-merge-compares-synthesised-ctors`); a derived
  `Eq` on a recursive type is not reflected (todo `2026-11-06-derived-eq-recursive-type-unreflected`;
  the theory uses its own `same`).

## Tests

`test_refinecheck` suite `session-theory` (6): the nine lemmas are in the manifest (its
freshness test makes that a proof); both projectors agree on two-role, three-role and
loop/choice protocols; an uninformed bystander is not compared; the endpoints constructor case;
`may crash` is outside the fragment; the `--guarantees` protocol lines. Suite `guarantees`
updated for the new projection line.

## Not covered

C3 (pairwise duality for more than two roles, to replace `project_protocol`'s existence
check), C4 (composition) and C5 (deadlock freedom for the fragment); crash branches.
