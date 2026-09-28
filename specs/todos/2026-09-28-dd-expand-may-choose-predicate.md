# `[P3]` Distributed deploys: an expand build gives chooser code no way to ask "may I choose?"

Found while writing `test/two_node/protocol_expand_contract` (2026-09-28, the D21 split in
`forge deploy`: [../progress/2026-09-28-dd-d21-split-in-forge-deploy.md](../progress/2026-09-28-dd-d21-split-in-forge-deploy.md)).

A monolith's expand and contract are the SAME source, built with and without
`--protocol-expand P:label`. In the expand, the chooser's generated `choose_<label>`
panics (lib/desugar/desugar_endpoints.ml, `held_labels`), so chooser code that calls it
kills its session, which is a lost session in the middle of a deploy that was meant to be safe. The only
way user code can tell the two builds apart today is by comparing fingerprints:

```march
Order_Msg.role_fingerprint(Order_Msg.role_Shop()) == Order_Msg.fingerprint()
```

That works (the scenario's `may_choose_later` does it), but nothing points a user at it
and forgetting it only fails at run time, during the expand.

**Fix.** Generate a predicate: `<P>_<Chooser>.may_choose_<label>() : Bool` (false only
in an expand build that holds `label`), or have the typechecker/linter warn when a
`choose_<label>` call is not guarded by it in a program that declares a topology. The
`forge deploy --plan` split text should then name the predicate instead of the
fingerprint comparison (docs/topology.md, specs/lang/choreography.md).
