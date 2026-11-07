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
