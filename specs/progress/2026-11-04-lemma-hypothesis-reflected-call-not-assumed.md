`[P2]` A lemma hypothesis that calls a reflected function is not assumed

Found 2026-11-04 on `b86c86a63` while probing the session-type lemmas
(`specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` §2, gap G1).

```march
mod Main do
  type G = GEnd | GMsg(Int, G)
  fn okz(g : G) : Bool do
    match g do
      GEnd -> true
      GMsg(s, k) -> s == 0 && okz(k)
    end
  end
  @[lemma]
  fn h4(g : {G | okz(_)}) : {Unit | okz(g)} do () end
  fn main() : Int do 0 end
end
```

`march --check --refine-report-sites=all` gives `skip reflect-fuel postcondition h4 okz(g)`
and `lemma_unproved` (0 of 1 paths): the theorem is the hypothesis verbatim. `_` or the
parameter's own name (`{G | okz(g)}`) make no difference, and neither does
`@[reflect(fuel: 4)]`. The same fact moved into the theorem as an implication,
`{Unit | !okz(g) || ...}`, proves. So a refined parameter whose predicate calls a reflected
function is not put into the lemma's proof context, while arithmetic hypotheses
(`n : {Int | _ >= 0}`, lemmas.md) are.

The hint makes it worse. For the inductive form of `project_dual` it says "the proof may
need more unfolding of `dual`", which sends the user to raise fuel, which can't help.

Done when `h4` proves, the inductive `project_dual` with `g : {Global | binary(_, a, b)}`
proves (design §2 P1), and a RED control shows the hypothesis is what proves it. Check that
callers are still obliged to prove the hypothesis (`lemma_unproved_call` otherwise).

## Fixed (2026-11-04)

Three causes, each on the path from a hypothesis to a proof:

1. **The hypothesis never reached the query.** A datatype parameter's promise is loaded from
   scope only for measures (`len(_) > 0`) and constructor tests (`is_Some(_)`); a conjunct
   calling a function, `okz(_)`, was dropped. `fnparams_call_facts`
   (`lib/refinecheck/refine_check.ml`) now puts each such conjunct (or its negation) into the
   body's path with `_` and the binder read as the parameter, beside `fnparams_field_facts`.
   A Bool call in the path is reflected, and unfolded by stage 2, like an `if okz(g)` guard.
   Callers are still obliged to prove it (`hyp_caller_obliged`).
2. **A callee's `okz(_)` was not the same predicate as its `okz(g)`.** In stage 2, `check_call`'s
   `resolve_var` gave the named spelling the parameter's datatype sort but reflected `_` and the
   binder at the scalar default, so `need(k)` against `{G | okz(_)}` met nothing
   (`lib/refinecheck/refine_call.ml`, the self branch).
3. **The induction hypothesis was withheld.** `ih_prepare`'s calls-only walk checks a recursive
   lemma call's preconditions with no lemma walk, so the match arms had no selector links
   (§4.3) and `okz(k)` could not follow from `okz(g)`. `lemma_body` now turns the links on for
   any walk of a valid lemma's body.

Tests (`test/test_refine_lemma.ml`, `hypotheses`, in group `reflect-lemma`): `h4` proves; its
RED control (no hypothesis) does not; the binder and the parameter's own name; a negated
call; the inductive `okz_cnt`; a callee spelled `okz(_)`, `okz(v)` and `okz(g)`;
`project_dual` with `g : {Global | binary(_, a, b)}` (design §2 P1, all 5 paths) and its
control without the hypothesis; a caller that breaks the hypothesis is reported.

Not changed: outside a lemma, a match arm still has no selector links (the §4.3 ruling), so an
ordinary function cannot get `okz(k)` from `okz(g)` and `g = GMsg(_, k)`. The "may need more
unfolding" hint the todo complained about was not reworded.
