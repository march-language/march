`[P1]` # Named process registry: hold names across a restart, not stale Pids

**Design spec:** [`specs/2026-08-12-named-registry-design.md`](../2026-08-12-named-registry-design.md)

## The gap

Supervision now self-heals with exponential backoff (2026-08-12 hardening,
Tasks 14-16), but a restarted child gets a **new** Pid. The supervisor writes
the new `pid_index` into its own state, so the *inside* of the tree recovers —
every holder **outside** it is left pointing at a dead incarnation. `get_cap`'s
epoch mechanism correctly *detects* the staleness, but nothing lets a holder
**re-resolve**: there is no local name → Pid mapping.

This is the missing half of the self-heal story. A supervision tree that heals
internally while every caller holds a dead handle has not healed the system.

## What every comparable runtime provides

- **BEAM:** `register/2` + `whereis/1`, `{via, Registry, …}`, `:global`.
  Elixir's `Registry` adds unique/duplicate keys and automatic cleanup.
- **Akka:** actor paths — the path outlives the incarnation.
- **Orleans:** goes furthest — you never hold a reference at all; you address a
  grain by identity and the runtime activates it on demand.

March has `stdlib/global_registry.march` and `stdlib/peer_registry.march` for
the **distributed** plane, but no local registry. The local plane is the weaker
one, which is backwards.

## Sketch

Full design in the spec above. In brief, mirroring Elixir's `Registry`
(which is built on ETS, not a bespoke structure): the data lives in **Vault**
— two tables, `name -> pid` and `pid -> names` — the policy lives in stdlib,
and only the cleanup *trigger* lives in the runtime, where `do_actor_death`
drops the entries. That last part is a deliberate divergence from Elixir, whose
EXIT-signal cleanup leaves a window in which a lookup can return a dead pid.

Restart survival needs no child-spec syntax change: `march_respawn_child`
carries the crashed incarnation's names forward.

**Depends on** `specs/todos/2026-08-12-vault-toward-ets-semantics.md` —
concurrent reads (lookups land on the send path) and typed handles (an erased
`Option(ptr)` would let a mistyped read be dereferenced as an actor record).
The capability question — every Vault op currently requires `IO.Mut` — is
answered for this feature by having the runtime own the well-known tables, so
`Actor.whereis` needs no capability at all.

## Acceptance

A supervised child registered under a name, killed repeatedly, is reachable by
that name after every restart — from a holder that never saw the new Pid.
