`[P2]` Session.Theory C3-C5: pairwise duality, composition and deadlock freedom (the fragment)

Phase C of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§5.3 C3, C4, C5),
after part one (progress `2026-11-06-session-theory-and-projection-validation`).

## The fragment

`Session.Theory.in_fragment(g, rs, multiparty)`: loop-free (`stop` is `GEnd`), crash-free,
every message between two different roles of `rs`, every choice DIRECTED (`choice_ok`: each
branch begins with the chooser's message to one receiver, `dest`), and every other role of
`rs` sees the branches alike (`role_ok`/`bystanders_merged`: `merged` projections). Delivery
is synchronous (design §5.3, open question 4: the asynchronous-simulated-by-synchronous
theorem is not attempted).

## Theory (stdlib/session_theory.march)

- Semantics: `Cfg` (role, local) list built by `config(g, rs, mp)`; `Act` is `AMsg(f, t, p)`
  or `APick(c, t, label, p)` (a choice's label rides on the chooser's first message);
  `step` (both parties present, each takes its part: `send_step`, `recv_step`, `choose_step`,
  `offer_step` from an offer or a merged receive); `run` over `Acts`; the protocol's own
  `trace(g, picks)`; `finished` (every role `LEnd`).
- C4 `compose`: `!in_fragment(g, rs, mp) || composes(g, rs, mp, picks)`, from subject
  reduction per step (`step_msg`, `step_pick`, built from per-role `act_msg`/`act_pick`), the
  per-head steps `compose_msg`/`compose_pick`, and `compose_bs` walking to the chosen branch.
- C5 `progress`: while `trace(g, picks)` has a step, `step(config(g, rs, mp), first_act(g,
  picks)) != Stuck`.
- C3 `pairwise`: for `p != q` in `rs`, `restrict(project(g, p), q) == dual(restrict(project(g,
  q), p))`. `restrict` keeps the actions with that peer, peers erased, and `collapse`s a choice
  whose restricted branches all look alike. The choice case is uniform
  (`restrict_choice`: `collapse(restricted branches, r == chooser)`), with `collapse_dual`,
  `merged_restrict`, `merged_dual`.
- Own list types (`Roles`, `Acts`, `Picks`) and hand-written `same` (a derived `Eq` on a
  recursive type is not reflected: todo `2026-11-06-derived-eq-recursive-type-unreflected`).
- 41 lemmas, all in `stdlib/lemmas.verified`.

## Compiler fix found on the way (refine_post.ml, `ih_rounds`)

The gate's induction-hypothesis rounds retried an ORDINARY pending lemma only when it called
a group admitted in the same round. A lemma that waited on another ordinary lemma proved by
`check` in the round before was never retried: `compose_msg` (needs `step_msg`, which needs
the `present_config`/`apply_msg` groups), `compose_pick` and `progress` stayed unadmitted
although every path proved, so their calls gave no facts and C4 could not combine them. Now
an item is also retried when it calls something proved in the previous round (`fresh`; the
first IH round has none). Regression: `session-theory` case "gate: a lemma waiting only on
an ordinary lemma proved in an IH round is admitted" (`add_z3`), red on the old compiler,
green on the new.

## Report

`bin/session_validate.ml`: `fragment name` evaluates `in_fragment` on the typechecker's view
over all its roles, and runs C4's instance (`composes` on the default schedule) as a guard
(false would mean an unsound proof: then nothing is claimed). `--validate-projections` adds a
`laws <P>: in the fragment …` / `outside the fragment: <why>` line. `bin/guarantees.ml`:
with the projection validated and the protocol in the fragment, `pairwise duality` (3+ roles)
and `deadlock freedom` are `proved (spec) · validated (compiler)`; otherwise
`checked (compiler)` / `not checked` with the reason (`a loop`, a choice whose other roles do
not see the same branches, or the projection not validated).

## Evidence

- The repo's protocols (217 files with a protocol under test/, examples/, stdlib/, docs/):
  972 projections agree, 0 differ; 137 protocols in the fragment, 85 outside for a loop, 22
  for a role that may crash. C4's instance evaluated true for every one in the fragment.
- Non-vacuity: `Relay`, `Ring` and the three-role directed choice are in the fragment; a loop
  and an uninformed bystander are out, each with its reason.

## Not covered

Loops (needs unfolding: the configuration after one iteration equals the start, design
§5.3 C4), crash branches, uninformed bystanders (`informed` but not `merged`), and replacing
`project_protocol`'s existence check with C3 (todo `2026-11-06-session-theory-loops-crash`).
