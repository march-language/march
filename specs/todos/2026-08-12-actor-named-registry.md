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

Full design in the spec above. In brief: a C-runtime name table beside
`g_actor_tbl` (so lookups don't need a message round-trip and can be reached
from the send path), automatic unregistration in `do_actor_death`, and
re-registration inside `march_respawn_child` so a restart reuses the crashed
incarnation's name without any child-spec syntax change.

## Acceptance

A supervised child registered under a name, killed repeatedly, is reachable by
that name after every restart — from a holder that never saw the new Pid.
