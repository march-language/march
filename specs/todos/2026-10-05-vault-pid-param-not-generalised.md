`[P3]` A function that stores a `Pid(a)` parameter in a `Vault` is not polymorphic in `a`

Found 2026-10-05 while fixing the cold/warm stdlib-cache divergence
(specs/progress/2026-10-05-cold-vs-warm-home-cache-tir-divergence.md).

`Topology.offer_actor_role(name, place, capacity, mk : () -> Pid(a), open :
Pid(a) -> Int -> Result(...))` keeps the `Pid(a)` it spawns in a
`Vault.new(...)`. After the stdlib check, `a` is still a free unification
variable in its scheme rather than a quantified one, so the first caller fixes
it for the whole program. Same shape in user code:

```march
fn mkrole(mk : () -> Pid(a), open : Pid(a) -> Int) : Int do
  let spare = Vault.new("x")
  pick(spare, mk, open)
end
-- pick(spare : Vault(Pid(a)), mk, open) does Vault.get / mk() / Vault.set
```

Calling `mkrole` with two different actors is rejected:
"expected `{ n : Int }` but got `{ s : String }`".

This may be deliberate: a Vault is a named, process-global table, so a
polymorphic `Vault.new("x")` would let two instantiations share one table at
two types (value-restriction-style soundness). But `offer_actor_role` names
its vault uniquely (`next_id()`), and a topology app with two actor-bound
roles of different state types should hit the same error (not yet tried). Decide whether
`offer_actor_role` should be restructured (e.g. store the pid erased), or
whether the restriction should be narrowed, and add a test with two
actor-bound roles of different state types.
