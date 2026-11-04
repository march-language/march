`[P3]` Protocol claims across messages: a payload refinement that names earlier messages

Filed 2026-11-04 from a design conversation; not scheduled. A user wants to state, in the
protocol, a claim about values that span one pass through a conversation, and have the
compiler prove it. Second phase (loops): `2026-11-04-protocol-loop-invariants`.

## What works today

A payload refinement that mentions only its own value is already an obligation on the
sender (checked 2026-11-04):

```march
@[endpoints]
protocol Fan2 do
  number: A -> C : {Int | _ >= 0}
  ...
end
-- Fan2_A.send_Number(s, st, 0 - 5)  =>  refinement_violated, "never satisfies it"
```

Not yet checked: whether the receiver gets `_ >= 0` as a fact on the value its callback
binds (`recv_Number(s, st, fn (a, st1) -> ...)`). Verify that first; it is half of this item.

## What is wanted

A payload refinement may name the payloads of earlier steps by their labels:

```march
@[endpoints]
protocol Fan do
  number:  A -> C : Int
  second:  B -> C : Int
  verdict: C -> A : {Bool | _ == decide(number, second)}
end
```

The claims this covers, all within one pass (one session, or one round of a loop):

| Claim | Example |
|---|---|
| Outcome decided by the input | the branch chosen / verdict sent `== classify(order)` |
| Validity | `Commit` is chosen only if every vote received was yes |
| Agreement | the decision sent to P1 equals the one sent to P2 |
| Integrity through a pipeline | stage 3 receives `g(f(x))` of what stage 1 sent |
| Scatter-gather | the parts sent to the workers cover the input; the gathered result `== f(input)` |
| Bounds | amount charged `<=` amount authorized |

"Each M ends in exactly one of N outcomes" is already given by the linear session types
(one `choose` branch per session); what this adds is tying *which* outcome to M's value.

## Shape of the design (sketch, not decided)

- **Sender proves, receiver assumes.** Projection turns the refinement into a precondition
  of the sending role's `send_X` (with the earlier labels bound to the values that role
  received or sent) and a fact on the receiving role's callback binder. The refinement
  checker already discharges preconditions at call sites, and lemmas about the decision
  function help.
- **Rule of thumb for checkability:** the claim is locally provable when the sending role
  has seen every value it names. When it has not, the receiver can still assume it (C
  proved it before sending), so a chain such as a pipeline works hop by hop.
- **Choices.** A refinement on a branch's first message is how "the chosen branch matches
  `classify(m)`" is stated; the chooser proves it.

## Open questions

- Label scoping: a label inside a `loop` refers to this round's value; a label in a
  branch not taken is out of scope. What is the error when a refinement names one?
- A role that never saw a named value: is the label a symbolic (unknown) value in its
  facts, and is that sound across a `may crash` / `or crash` branch?
- Trust boundary: messages from another node are assumed, not enforced
  (`specs/lang/refinement-types.md`). The receiver's assumption is sound only if the
  sender was compiled against the same refinement, so refinements probably belong in the
  protocol fingerprint (today grants are excluded; payload types are in). Compare the HCR
  variance check (PR #1100) for how a deployed protocol's refinements may change.
- Reflection: the refinement calls user functions (`decide`, `classify`), which must be
  reflectable; report an unreflectable one at the protocol, not at a generated `send_X`.
- Diagnostics must name the protocol step and the user's role function, never the
  generated `Fan_C.send_Verdict` alone (see `2026-11-02-diag-choreography-session-messages`).

Related: `2026-11-04-lemmas-hcr-actors-choreography` (protocol meta-theory: projection,
duality, deadlock freedom; this item is about user values, not the protocol's shape).
