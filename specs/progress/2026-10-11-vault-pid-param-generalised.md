# `[P3]` A function that stores a `Pid(a)` parameter in a `Vault` is not polymorphic in `a`

**Fixed 2026-10-11** (typechecker; see Resolution below).

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

## Resolution (2026-10-11)

Not specific to `Pid`: any type variable that a parameter names and that
reaches a Vault bound by an unannotated block `let` was pinned
(`fn keep(x : a) do let t = Vault.new("y") Vault.set(t, "k", x) end` had the
same bug). The cause was the block-`let` Vault value restriction
(`demote_vault_handle_vars`, `lib/typecheck/typecheck_env.ml`): it demoted
every variable under the handle's `Vault(...)` to level 0, which pins it for
the whole program. Unifying the handle's element type with `Pid(a)` then
lowered `a` to level 0 too, so `check_fn` never generalized it.

**Fix.** The restriction is narrowed, not dropped. `check_fn` opens a pin frame
(`with_vault_pin_frame`). A block `let` inside it demotes the handle's vars only
to the fn's body level and records the type
(`demote_block_vault_handle_vars`): nothing inside the body (a `let`, a local
fn) can generalize them, so every use within one call still shares one element
type. Just before the fn generalizes, `settle_vault_pins` demotes to level 0
the recorded vars that no parameter type mentions. A var a parameter names is
chosen by each caller through its arguments and generalizes with the function.
A var only the body or the return type names
(`fn peek() : Option(b) do Vault.get(Vault.open("shared"), "k") end`) stays
pinned program-wide, as before, so a named table still cannot be read back at
two types through such a reader. A `let` outside any fn (module-level, or no
frame) keeps the old level-0 behaviour.

The soundness caveat in the original note still applies to the
parameter-named case: two instantiations of `keep` that reach the same table
by NAME (`Vault.open("x")`) could store at one type and read at another. That
is the same name-keyed erasure `Vault.open`/`whereis` already document
("two `Vault.open` calls on the same name may pick different `v`"); the typed
handle protects a handle, not a name. `offer_actor_role` names its table
uniquely, so it is unaffected, and it needed no change.

**Tests.** `specs/lang/types/accept/t314_vault_param_tyvar_generalises.march`
(the repro, a `Pid(a)` and a plain `a`; also run on both backends: prints
`1`, `2`, `2`), `accept/t316_topology_two_actor_roles.march` (two
`Topology.offer_actor_role` roles over actors with different state types),
both rejected before the fix; and `reject/t315_vault_body_only_tyvar_stays_pinned.march`,
which pins that a body-only variable is still monomorphic.
