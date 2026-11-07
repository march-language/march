`[P2]` Mixed-version protocol compatibility for rolling deploys, checked against the session theory.

Rung 2 of the distributed-proof ladder (2026-11-06 discussion).

## The problem

During a rolling deploy, an old-version node and a new-version node talk on the same
protocol. Mixed-version message mismatches are a leading cause of upgrade outages in
distributed systems, and they are almost never checked against the code. March already plans
deploys around them: `forge/lib/protocol_split.ml` (D21) classifies a protocol change as
unchanged, a choice that can be split into expand/contract, or breaking, from the deployed
baselines (`.forge/deploy/<env>/protocols`) and this build's (`.forge/protocols`). That
classification is a set of rules in OCaml; nothing proves that the old and new roles still
form a valid protocol together.

## What it gives

For each protocol changed by a deploy, and each pair (old role A, new role B) that can meet
during the rollout, a proof that A's projection and B's projection are dual (or that B's is a
session subtype of what A expects), in the synchronous, crash-free fragment
`stdlib/session_theory.march` covers. A pair that is not compatible is a refused deploy with
the first diverging step, exactly as an unproved migration is refused today (with the same
audited override, `--accept-unproved`).

## Builds on

- `Session.Theory` (phase C): duality, projection, pairwise duality (C3), composition; both
  OCaml projectors validated against it by interpreter evaluation.
- The protocol baselines and the expand/contract split plan (`Protocol_split.changes_of_dirs`,
  `split_plan`), and `forge hot-reload check` / `march --check --guarantees` (phase B) for the
  report line.

## Shape

1. Session subtyping in `Session.Theory` (send covariant in labels it may drop, receive
   contravariant: the standard rules), proved like C1/C2.
2. A check that, per changed protocol, evaluates old-vs-new compatibility for every role pair
   the rollout order allows (receivers first, as the split plan already orders them).
3. Translation validation of `Protocol_split`'s classification against it: every change it
   calls safe must be proved compatible; disagreements are bugs in one of the two.
4. The deploy gate reads the verdict; `--guarantees` prints one line per protocol
   (`proved (theory)`, `refused: <step>`).

## Done when

- The `protocol` and `hosted_protocol_change` two-node scenarios' changes are proved
  compatible; a fixture that adds a required reply label without an expand step is refused
  with the diverging step.
- `Protocol_split`'s existing test cases (`separate pools`, `monolith`, `breaking and
  unchanged`) agree with the theory's verdicts.
