# Supervised children never get their capabilities captured at spawn

**Status:** filed 2026-09-03 out of `2026-09-02-lift-one-cap-per-actor.md`
(now in `specs/progress/`), which lifted the one-capability-per-actor limit on
capture at spawn and deliberately left this gap alone. Pre-existing; it is
independent of how many capabilities an actor needs.

## The gap

`lib/tir/cap_passing.ml`'s `thread` captures capabilities onto an actor's
runtime metadata by matching EXACTLY the shape `lower` emits for a plain
`spawn(Name)`:

```
let $raw_actor = Name_spawn() in spawn($raw_actor)
```

A `supervise` block's children are spawned through a different builtin and a
different shape. `lib/tir/lower_actor.ml` binds each declared child with
`$sup_child_raw_<field> = Child_spawn()` and hands it to `spawn_supervised`
(around L350–L370), then `wrap_sup` (around L453) registers each child with
the supervisor after the supervisor's own `spawn`. The capture pattern does not
see any of that, so a supervised child's dispatch reads back an empty slot and
its operations run unmocked — `actor_caps` returns the sentinel, exactly as
every actor did before #397. A mock reaching the supervisor itself does not
propagate: the child is a separate actor with its own metadata.

## What to build

A second pattern in `thread`, next to the plain-spawn one, that recognises
the `spawn_supervised` shape and attaches the same capability record after the
runtime call that creates the child's metadata (`march_spawn_supervised`, like
`march_spawn`, is what creates it, so the setter has to follow it). It must
share `dispatch_caps` / `spawn_caps` with the plain path so the two cannot
disagree about WHICH capabilities a child needs; the record shape, field
names, and the dispatch-side projection are unchanged.

Keep the two patterns distinct in code and in tests: the plain-spawn one is
guarded by `test/cap_mock/cap_mock_actor.march` and
`test/cap_mock/cap_mock_actor_two.march`, and neither exercises a supervisor.

## Test

A golden under `test/cap_mock/` (compiled `--test` only, like the other
`cap_mock_*` rules in `test/dune`): a supervisor with one declared child whose
handler performs an interceptable `IO.Console` builtin, started inside
`with_cap`, and the child's output must come through the mock. Red control
first: without the second pattern the child's line is unmocked.

## Out of scope

Children spawned dynamically by a supervisor at runtime (not declared in the
block) go through whichever shape their spawn site lowers to; check which
before assuming they are covered.
