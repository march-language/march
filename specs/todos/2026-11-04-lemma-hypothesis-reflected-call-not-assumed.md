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
