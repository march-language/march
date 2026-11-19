# `IO.Registry` operations have no run-time check (2026-11-19)

Found by the ocap phase 4 PR B final review (Minor 7). `Actor.register`,
`Actor.unregister`, `Actor.whereis` and `Actor.registered`
(`stdlib/actor.march`) are charged `IO.Registry` at compile time and judged
against name scopes, but run no `Authority.check` and return no `Result`, so a
narrowed launch (`MARCH_GRANT`) or a scoped function `needs IO.Registry("name")`
does not limit them at run time. `actor_register` and `actor_unregister` are
also not stdlib-only (`lib/caps/cap_ops.ml`, `~gated:false`), so user code can
call them directly.

The allowlist rows in `test/test_cap_check_coverage.ml` and the comment at the
IO.Registry rows of `lib/caps/cap_ops.ml` point here; the CHANGELOG's run-time
authority entry lists it as not yet covered.

What to do: give the four wrappers an `Authority.check("IO.Registry", name)` and
a `Result(_, CapError)` return (migrating callers), gate `actor_register` /
`actor_unregister`, delete the four allowlist rows, and add a
`test/cap_conformance` fixture for a refused register.
