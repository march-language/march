`[P2]` Session.Theory C3-C5 beyond the fragment: loops, crash branches, told-later bystanders

Progress `2026-11-06-session-theory-c3-c5` proves pairwise duality (C3), composition (C4) and
deadlock freedom (C5) for loop-free, crash-free protocols whose choices are directed and whose
other roles see the branches alike (`Session.Theory.in_fragment`). Out of it, the guarantee
report says `not checked` with the reason.

Open, in the order the design gives (§5.3):

1. **Loops.** `GLoop(body, after)`: unroll once; the configuration after one iteration is the
   starting one again (an equality of finite terms, not coinduction). Needs `LRec` steps in the
   semantics (unfold `LRec(b)` to `b[LRec(b)/LVar 0]`) and a substitution lemma
   (`project` commutes with unfolding). Most real protocols loop, so this is the next one.
2. **Told-later bystanders.** A role whose branches differ but that learns the label from the
   chooser's message later in the branch (`informed`, not `merged`). Subject reduction needs
   a refinement relation (the offer is pending until its message arrives), not equality.
3. **Crash branches.** `ProtoCrashOr` / `may crash` (`LRecvCrash` in the endpoints view).
4. **Replace `project_protocol`'s existence check** (typecheck_session.ml) with C3 for
   protocols in the fragment, as the design proposes.
5. The asynchronous semantics simulated by the synchronous one (design §8 question 4).

## Research constraints on extending the fragment (2026-11-07)

[Rast, LMCS 2022](https://arxiv.org/abs/2012.13129) offers arithmetic-indexed and resource-aware
sessions. Its work/span and protocol results are relative to its calculus; they do not supply
March's crash or asynchronous semantics.

- Unrolling once is a proof step, not by itself a proof for arbitrary loop iterations. State
  the preserved configuration relation and prove a recursive preservation/simulation theorem,
  with projection/substitution and binder scope lemmas. If restricted loops permit equality
  of configurations, demonstrate that restriction; include queued messages in the relation.
- Separate protocol fidelity, deadlock freedom, termination and eventual delivery. Infinite
  protocol loops need not terminate. State fairness and delivery assumptions for liveness;
  actor failure and partitions do not satisfy a crash-free theorem's assumptions.
- Make asynchronous semantics a separate gate: model queues, permitted buffering, FIFO scope
  and failures, and prove the correspondence actually required. Do not promote a synchronous
  theorem to an asynchronous runtime guarantee on the basis of trace tests alone.
- Acceptance includes nested loops, a bystander learning the choice later, a crash while a
  receive is pending and a buffered-send schedule. Unsupported cases remain `not checked`.

Resource-indexed protocols are a separate P4 experiment
(`2026-11-07-resource-indexed-protocol-experiment`), not a prerequisite for closing these gaps.
